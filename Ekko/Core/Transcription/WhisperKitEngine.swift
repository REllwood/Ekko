import Foundation
import WhisperKit

// WhisperKit exports its own `TranscriptionResult`/`TranscriptionSegment`, so Ekko's types are
// spelled out with the module name inside this file.

/// WhisperKit-backed engine.
///
/// All model work is funnelled through a private actor, so `load`, `unload` and `transcribe` can
/// never overlap and none of them touch the main thread.
final class WhisperKitEngine: TranscriptionEngine {
    private let core = WhisperKitCore()

    init() {}

    var loadedModelID: ModelID? {
        get async { await core.loadedModelID }
    }

    func load(model: ModelDescriptor, folder: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        try await core.load(model: model, folder: folder, progress: progress)
    }

    func unload() async {
        await core.unload()
    }

    func transcribe(_ audio: AudioBuffer16k, options: TranscriptionOptions) async throws -> Ekko.TranscriptionResult {
        try await core.transcribe(audio, options: options)
    }
}

// MARK: - Serialised WhisperKit access

private actor WhisperKitCore {
    private var whisperKit: WhisperKit?
    private var model: ModelDescriptor?
    /// Actors are re-entrant: while a transcription is suspended inside WhisperKit, a `load` or
    /// `unload` call could run and pull the model out from under it. They wait for this to reach 0.
    private var transcriptionsInFlight = 0

    var loadedModelID: ModelID? { model?.id }

    func load(model: ModelDescriptor, folder: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard FileManager.default.fileExists(atPath: folder.path) else {
            throw TranscriptionEngineError.modelFolderMissing(folder.path)
        }
        await unload()
        progress(0.02)

        let base = ModelStorage.defaultDownloadBase
        let config = WhisperKitConfig(
            downloadBase: base,
            modelFolder: folder.path,
            tokenizerFolder: base,
            computeOptions: Self.computeOptions(),
            verbose: false,
            logLevel: .error,
            prewarm: false,
            load: false,
            download: false
        )

        do {
            // Built without prewarm/load so the state callback can be attached first; the two
            // phases below are then reported as real progress.
            let kit = try await WhisperKit(config)
            kit.modelStateCallback = { _, state in
                progress(Self.fraction(for: state))
            }
            try Task.checkCancellation()
            try await kit.prewarmModels()
            try Task.checkCancellation()
            try await kit.loadModels()

            self.whisperKit = kit
            self.model = model
            progress(1)
            Log.models.info("Loaded \(model.id, privacy: .public)")
        } catch is CancellationError {
            throw TranscriptionEngineError.cancelled
        } catch {
            whisperKit = nil
            self.model = nil
            throw TranscriptionEngineError.loadFailed(
                "\(model.displayName) could not be loaded. \(error.localizedDescription)"
            )
        }
    }

    func unload() async {
        while transcriptionsInFlight > 0 {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        guard let kit = whisperKit else { return }
        await kit.unloadModels()
        whisperKit = nil
        model = nil
    }

    func transcribe(_ audio: AudioBuffer16k, options: TranscriptionOptions) async throws -> Ekko.TranscriptionResult {
        guard let kit = whisperKit, let model else {
            throw TranscriptionEngineError.noModelLoaded
        }
        transcriptionsInFlight += 1
        defer { transcriptionsInFlight -= 1 }
        let clock = ContinuousClock()
        let started = clock.now

        guard !audio.isEmpty else {
            return Ekko.TranscriptionResult(
                text: "",
                detectedLanguageCode: nil,
                segments: [],
                processingTime: 0,
                isLikelySilence: true
            )
        }

        let decodeOptions = Self.decodingOptions(for: options, model: model, audio: audio, tokenizer: kit.tokenizer)
        let nearSilence = audio.rms < HallucinationFilter.silenceRMS

        do {
            let results = try await kit.transcribe(audioArray: audio.samples, decodeOptions: decodeOptions)

            var segments: [Ekko.TranscriptionSegment] = []
            for result in results {
                for segment in result.segments {
                    if HallucinationFilter.isNoise(
                        text: segment.text,
                        noSpeechProbability: segment.noSpeechProb,
                        averageLogProbability: segment.avgLogprob,
                        nearSilence: nearSilence
                    ) { continue }

                    let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    segments.append(
                        Ekko.TranscriptionSegment(
                            start: TimeInterval(segment.start),
                            end: TimeInterval(segment.end),
                            text: text,
                            noSpeechProbability: segment.noSpeechProb,
                            averageLogProbability: segment.avgLogprob
                        )
                    )
                }
            }

            return Self.makeResult(
                segments: segments,
                detectedLanguage: results.first?.language,
                processingTime: Self.seconds(from: started, to: clock.now)
            )
        } catch is CancellationError {
            throw TranscriptionEngineError.cancelled
        } catch {
            throw TranscriptionEngineError.transcriptionFailed(error.localizedDescription)
        }
    }

    // MARK: - Configuration

    private static func computeOptions() -> ModelComputeOptions {
        #if arch(arm64)
        // The Neural Engine is both the fastest and the most power-efficient path on Apple Silicon.
        return ModelComputeOptions(
            melCompute: .cpuAndGPU,
            audioEncoderCompute: .cpuAndNeuralEngine,
            textDecoderCompute: .cpuAndNeuralEngine
        )
        #else
        return ModelComputeOptions(
            melCompute: .cpuAndGPU,
            audioEncoderCompute: .cpuAndGPU,
            textDecoderCompute: .cpuAndGPU
        )
        #endif
    }

    private static func fraction(for state: ModelState) -> Double {
        switch state {
        case .unloading, .unloaded: return 0
        case .downloading: return 0.05
        case .downloaded: return 0.1
        case .prewarming: return 0.2
        case .prewarmed: return 0.55
        case .loading: return 0.65
        case .loaded: return 1
        }
    }

    private static func decodingOptions(
        for options: TranscriptionOptions,
        model: ModelDescriptor,
        audio: AudioBuffer16k,
        tokenizer: WhisperTokenizer?
    ) -> DecodingOptions {
        // English-only models have no language tokens, so auto-detection must stay off.
        let language = model.isEnglishOnly ? "en" : options.languageCode
        let detectLanguage = model.isEnglishOnly ? false : (options.languageCode == nil)
        var promptTokens: [Int]?
        if let prompt = options.prompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !prompt.isEmpty,
           let tokenizer {
            let tokens = tokenizer.encode(text: prompt)
            promptTokens = tokens.isEmpty ? nil : tokens
        }
        // Anything longer than one Whisper window is split on voice activity instead of on time.
        let chunking: ChunkingStrategy? = audio.duration > 30 ? .vad : nil

        return DecodingOptions(
            verbose: false,
            task: options.task == .translate ? .translate : .transcribe,
            language: language,
            temperature: 0,
            temperatureFallbackCount: 3,
            usePrefillPrompt: true,
            detectLanguage: detectLanguage,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            wordTimestamps: false,
            promptTokens: promptTokens,
            suppressBlank: true,
            compressionRatioThreshold: 2.4,
            logProbThreshold: -1.0,
            noSpeechThreshold: 0.6,
            chunkingStrategy: chunking
        )
    }

    // MARK: - Result mapping

    private static func makeResult(
        segments: [Ekko.TranscriptionSegment],
        detectedLanguage: String?,
        processingTime: TimeInterval
    ) -> Ekko.TranscriptionResult {
        let text = collapseWhitespace(segments.map(\.text).joined(separator: " "))
        let detected = detectedLanguage?.trimmingCharacters(in: .whitespaces)

        return Ekko.TranscriptionResult(
            text: text,
            detectedLanguageCode: (detected?.isEmpty ?? true) ? nil : detected,
            segments: segments,
            processingTime: processingTime,
            isLikelySilence: segments.isEmpty || text.isEmpty
        )
    }

    /// Collapses runs of whitespace (including the newlines Whisper sometimes emits) into one space.
    private static func collapseWhitespace(_ text: String) -> String {
        text
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func seconds(from start: ContinuousClock.Instant, to end: ContinuousClock.Instant) -> TimeInterval {
        let duration = end - start
        return TimeInterval(duration.components.seconds) + TimeInterval(duration.components.attoseconds) * 1e-18
    }
}

// MARK: - Hallucination filtering

/// Whisper invents filler when it is handed silence or noise. Two signals catch nearly all of it:
/// the model's own no-speech confidence, and a short list of phrases it reaches for when there is
/// nothing to transcribe.
enum HallucinationFilter {
    /// Below this whole-utterance RMS we treat the recording as silence.
    static let silenceRMS: Float = 0.006
    static let noSpeechThreshold: Float = 0.6
    static let logProbabilityThreshold: Float = -1.0

    /// Phrases Whisper emits for silence, normalised (lowercased, punctuation stripped).
    static let silencePhrases: Set<String> = [
        "you",
        "blank audio",
        "bye",
        "bye bye",
        "thank you",
        "thanks",
        "thank you very much",
        "thanks for watching",
        "thank you for watching",
        "thanks for watching and dont forget to subscribe",
        "please subscribe",
        "subscribe to my channel",
        "like and subscribe",
        "music",
        "applause",
        "silence",
        "the end",
        "okay",
        "uh",
        "um",
        "hmm",
        "so",
    ]

    /// Prefixes of the credits Whisper copies from subtitle training data.
    static let creditPrefixes = [
        "subtitles by",
        "subtitled by",
        "subtitles and corrections by",
        "transcription by",
        "translated by",
        "amara org",
        "www",
        "http",
    ]

    static func isNoise(
        text: String,
        noSpeechProbability: Float,
        averageLogProbability: Float,
        nearSilence: Bool
    ) -> Bool {
        if noSpeechProbability > noSpeechThreshold && averageLogProbability < logProbabilityThreshold {
            return true
        }
        // Sound-event annotations are never dictation, however confident the model is.
        if isNonSpeechMarker(text) { return true }
        guard nearSilence else { return false }

        let normalized = normalize(text)
        if normalized.isEmpty { return true }
        if silencePhrases.contains(normalized) { return true }
        return creditPrefixes.contains { normalized.hasPrefix($0) }
    }

    /// Whisper labels sounds it cannot transcribe instead of staying quiet: "[BLANK_AUDIO]",
    /// "(smooth music)", "♪♪♪". Those labels are noise in a dictation app, at any volume.
    static func isNonSpeechMarker(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        // Nothing but punctuation, music notes or symbols.
        if trimmed.allSatisfy({ !$0.isLetter && !$0.isNumber }) { return true }

        let isWrapped = (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
            || (trimmed.hasPrefix("(") && trimmed.hasSuffix(")"))
            || (trimmed.hasPrefix("*") && trimmed.hasSuffix("*"))
        guard isWrapped else { return false }
        // Only when the annotation is the whole segment and stays short, so dictated asides survive.
        return normalize(trimmed).split(separator: " ").count <= 6
    }

    /// Lowercased, punctuation- and symbol-free, single-spaced.
    static func normalize(_ text: String) -> String {
        let stripped = text.lowercased().unicodeScalars.map { scalar -> Character in
            if CharacterSet.punctuationCharacters.contains(scalar) || CharacterSet.symbols.contains(scalar) {
                return " "
            }
            return Character(scalar)
        }
        return String(stripped)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}

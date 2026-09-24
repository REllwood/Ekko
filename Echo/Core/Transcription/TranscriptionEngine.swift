import Foundation

/// Catalog identifier of a model (the Hugging Face folder name, e.g. "openai_whisper-base").
typealias ModelID = String

/// A speech-to-text engine. Implementations must be safe to call from any actor; heavy work
/// must not block the main thread. One engine holds at most one loaded model.
protocol TranscriptionEngine: AnyObject {
    /// Catalog id of the loaded model, or nil.
    var loadedModelID: ModelID? { get async }

    /// Loads (and prewarms) the model stored in `folder`. `progress` is 0...1 and may be called
    /// from any thread. Replaces any previously loaded model.
    func load(model: ModelDescriptor, folder: URL, progress: @escaping @Sendable (Double) -> Void) async throws

    func unload() async

    /// Transcribes a complete utterance.
    func transcribe(_ audio: AudioBuffer16k, options: TranscriptionOptions) async throws -> TranscriptionResult
}

struct TranscriptionOptions: Sendable, Equatable {
    /// ISO 639-1 code (Whisper's set). `nil` = auto-detect.
    var languageCode: String?
    var task: TranscriptionTask = .transcribe
    /// Optional text prompt to bias vocabulary/style (Whisper "initial prompt").
    var prompt: String?

    init(languageCode: String? = nil, task: TranscriptionTask = .transcribe, prompt: String? = nil) {
        self.languageCode = languageCode
        self.task = task
        self.prompt = prompt
    }
}

enum TranscriptionTask: String, Sendable, Codable {
    case transcribe
    case translate
}

struct TranscriptionResult: Sendable, Equatable {
    /// Cleaned, joined text. Empty when nothing intelligible was heard.
    var text: String
    var detectedLanguageCode: String?
    var segments: [TranscriptionSegment]
    /// Wall-clock seconds spent in the engine.
    var processingTime: TimeInterval
    /// True when the engine judged the audio to be silence/noise (e.g. high no-speech probability).
    var isLikelySilence: Bool
}

struct TranscriptionSegment: Sendable, Equatable {
    var start: TimeInterval
    var end: TimeInterval
    var text: String
    var noSpeechProbability: Float?
    var averageLogProbability: Float?
}

enum TranscriptionEngineError: Error, LocalizedError, Equatable {
    case noModelLoaded
    case modelFolderMissing(String)
    case loadFailed(String)
    case transcriptionFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noModelLoaded: return "No speech model is loaded."
        case .modelFolderMissing(let path): return "Model files were not found at \(path)."
        case .loadFailed(let detail): return detail
        case .transcriptionFailed(let detail): return detail
        case .cancelled: return "Cancelled."
        }
    }
}

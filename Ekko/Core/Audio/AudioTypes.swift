import Foundation

/// Mono, 16 kHz, Float32 PCM in -1...1 — the only audio format the engine accepts.
struct AudioBuffer16k: Sendable, Equatable {
    static let sampleRate: Double = 16_000

    var samples: [Float]

    init(samples: [Float] = []) {
        self.samples = samples
    }

    var duration: TimeInterval { Double(samples.count) / Self.sampleRate }
    var isEmpty: Bool { samples.isEmpty }

    /// Root-mean-square level of the whole buffer (0...1).
    var rms: Float {
        guard !samples.isEmpty else { return 0 }
        var acc: Float = 0
        for s in samples { acc += s * s }
        return (acc / Float(samples.count)).squareRoot()
    }

    var peak: Float {
        samples.reduce(0) { max($0, abs($1)) }
    }

    /// Seconds of audio, in 20 ms frames, whose level is above `threshold`. Tells a real utterance
    /// apart from silence with a click or a short sound cue in it, which whole-clip RMS cannot.
    func audibleDuration(threshold: Float, frameLength: Int = 320) -> TimeInterval {
        guard frameLength > 0, !samples.isEmpty else { return 0 }
        var audibleFrames = 0
        var index = 0
        while index < samples.count {
            let end = min(index + frameLength, samples.count)
            var sum: Float = 0
            for i in index..<end { sum += samples[i] * samples[i] }
            if (sum / Float(end - index)).squareRoot() > threshold { audibleFrames += 1 }
            index = end
        }
        return Double(audibleFrames * frameLength) / Self.sampleRate
    }
}

/// A selectable microphone. `id` is the CoreAudio device UID; the system default is represented
/// by `nil` in settings, not by an entry here.
struct AudioInputDevice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let isSystemDefault: Bool
}

enum AudioCaptureError: Error, LocalizedError, Equatable {
    case permissionDenied
    case deviceUnavailable(String)
    case engineFailed(String)
    case notCapturing

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Microphone access was denied."
        case .deviceUnavailable(let name): return "The microphone “\(name)” is unavailable."
        case .engineFailed(let detail): return detail
        case .notCapturing: return "Not recording."
        }
    }
}

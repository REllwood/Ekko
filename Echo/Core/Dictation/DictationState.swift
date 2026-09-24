import Foundation

/// The dictation state machine. Only `DictationController` mutates it; the UI observes it.
enum DictationState: Equatable {
    case idle
    /// Loading the model or opening the microphone.
    case preparing
    /// Microphone open, audio accumulating.
    case listening
    /// Audio captured, engine running.
    case transcribing
    /// Text is being placed into the target app.
    case inserting
    /// A terminal failure; the controller returns to `.idle` after a short delay.
    case failed(DictationFailure)

    var isActive: Bool {
        switch self {
        case .idle, .failed: return false
        case .preparing, .listening, .transcribing, .inserting: return true
        }
    }

    var isListening: Bool {
        if case .listening = self { return true }
        return false
    }
}

enum DictationFailure: Equatable, Error, LocalizedError {
    case microphoneDenied
    case accessibilityDenied
    case noModelInstalled
    /// The model is still loading; the user let go before the microphone could open.
    case modelStillLoading
    case modelLoadFailed(String)
    case audioFailed(String)
    case transcriptionFailed(String)
    case insertionFailed(String)
    /// Recording was too short or silent.
    case nothingHeard
    /// Not a failure: the user just allowed the microphone from a dictation attempt. Nothing was
    /// recorded; the next attempt works.
    case microphoneReady

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: return "Echo needs microphone access to hear you."
        case .accessibilityDenied: return "Echo needs Accessibility access to type into other apps."
        case .noModelInstalled: return "Download a speech model to start dictating."
        case .modelStillLoading: return "The speech model is still loading. Try again in a moment."
        case .modelLoadFailed(let detail): return "The speech model could not be loaded. \(detail)"
        case .audioFailed(let detail): return "The microphone could not be started. \(detail)"
        case .transcriptionFailed(let detail): return "Transcription failed. \(detail)"
        case .insertionFailed(let detail): return "The text could not be inserted. \(detail)"
        case .nothingHeard: return "Nothing heard."
        case .microphoneReady: return "Microphone access is on. Start dictating again."
        }
    }

    /// Short label for the HUD.
    var hudTitle: String {
        switch self {
        case .microphoneDenied: return "Microphone access needed"
        case .accessibilityDenied: return "Accessibility access needed"
        case .noModelInstalled: return "No model installed"
        case .modelStillLoading: return "Still loading the model…"
        case .modelLoadFailed: return "Model failed to load"
        case .audioFailed: return "Microphone error"
        case .transcriptionFailed: return "Transcription failed"
        case .insertionFailed: return "Copied to clipboard"
        case .nothingHeard: return "Nothing heard"
        case .microphoneReady: return "Microphone ready"
        }
    }
}

/// One completed dictation, kept in the in-memory/persisted history.
struct TranscriptEntry: Identifiable, Equatable, Codable, Sendable {
    var id: UUID = UUID()
    var text: String
    var date: Date = Date()
    /// Seconds of audio captured.
    var audioDuration: TimeInterval
    /// Wall-clock seconds spent in the engine.
    var processingTime: TimeInterval
    var languageCode: String?
    var modelID: ModelID
    var targetAppName: String?
    var targetAppBundleID: String?
}

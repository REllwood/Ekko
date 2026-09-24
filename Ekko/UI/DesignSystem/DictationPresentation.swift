import SwiftUI

/// One place that maps `DictationState` to the words, glyphs and colours the UI shows.
enum DictationPresentation {

    static func title(for state: DictationState) -> String {
        switch state {
        case .idle: return "Ready"
        case .preparing: return "Getting ready…"
        case .listening: return "Listening…"
        case .transcribing: return "Transcribing…"
        case .inserting: return "Inserted"
        case .failed(let failure): return failure.hudTitle
        }
    }

    /// Like `title(for:)`, but says what "preparing" really means while the model loads.
    static func title(for state: DictationState, isModelLoading: Bool) -> String {
        if state == .preparing, isModelLoading { return "Loading speech model…" }
        return title(for: state)
    }

    /// Shown wherever a model load is in progress. The first load compiles the model for this
    /// Mac's Neural Engine, which is slow once and fast forever after.
    static let modelLoadingExplanation =
        "Preparing the speech model for this Mac. The first time can take a few minutes; after that it starts instantly."

    /// Longer line for the popover header.
    static func detail(for state: DictationState) -> String? {
        switch state {
        case .idle: return nil
        case .preparing: return "Loading the model and opening the microphone."
        case .listening: return "Speak now. Press your shortcut or click Stop when you're done."
        case .transcribing: return "Working on this Mac. No audio leaves your device."
        case .inserting: return "Placing the text where your cursor is."
        case .failed(let failure): return failure.errorDescription
        }
    }

    static func glyph(for state: DictationState) -> String {
        switch state {
        case .idle: return "mic"
        case .preparing: return "hourglass"
        case .listening: return "mic.fill"
        case .transcribing: return "waveform"
        case .inserting: return "checkmark"
        case .failed(.insertionFailed): return "doc.on.clipboard"
        case .failed(.microphoneReady): return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        }
    }

    static func dot(for state: DictationState) -> StatusDot.State {
        switch state {
        case .idle: return .idle
        case .preparing, .transcribing, .inserting: return .warning
        case .listening: return .live
        case .failed: return .error
        }
    }

    static func tint(for state: DictationState) -> Color {
        switch state {
        case .idle: return EkkoColor.inkMuted
        case .preparing, .transcribing: return EkkoColor.accent
        case .listening: return EkkoColor.live
        case .inserting, .failed(.microphoneReady): return EkkoColor.success
        case .failed: return EkkoColor.warning
        }
    }

    /// Second line under the HUD title: what to do next, when there is something to do.
    static func hudSubtitle(for state: DictationState, isModelLoading: Bool) -> String? {
        switch state {
        case .preparing:
            return isModelLoading ? "First run can take a few minutes" : nil
        case .failed(let failure):
            switch failure {
            case .insertionFailed: return "Press ⌘V to paste it"
            case .nothingHeard: return "Try again, a little closer to the mic"
            case .microphoneDenied, .accessibilityDenied: return "Allow it in Ekko › Permissions"
            case .noModelInstalled: return "Choose one from Ekko's menu"
            case .modelStillLoading: return "Try again in a moment"
            case .modelLoadFailed, .audioFailed, .transcriptionFailed: return "Details are in Ekko's menu"
            case .microphoneReady: return "Start dictating again"
            }
        case .idle, .listening, .transcribing, .inserting:
            return nil
        }
    }

    /// Compact language tag for the HUD: "Auto" or the code, e.g. "EN".
    static func shortLanguageLabel(for code: String?) -> String {
        guard let code else { return "Auto" }
        return code.uppercased()
    }

    static func elapsedString(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    static func languageLabel(for code: String?) -> String {
        guard let code else { return "Auto-detect" }
        return Language.named(code)?.englishName ?? code.uppercased()
    }
}

import Foundation

/// Pure translation of raw hotkey press/release/interrupt events into dictation actions for each
/// `ActivationMode`. Kept separate from `DictationController` so the mode logic can be unit-tested
/// with synthetic timestamps.
struct ActivationResolver: Equatable, Sendable {
    enum Action: Equatable, Sendable {
        case start
        case stop
        /// Discard the session silently (it was started by a keypress that turned out to be typing).
        case cancel
        case none
    }

    /// How long the key must be held for `.auto` to treat the gesture as push-to-talk.
    static let holdThreshold: TimeInterval = 0.5

    var holdThreshold: TimeInterval = ActivationResolver.holdThreshold

    /// When the key currently down was pressed, if any.
    private(set) var pressTimestamp: Date?
    /// True when the press that is still down is the one that started the current session.
    private(set) var startedOnCurrentPress = false

    init(holdThreshold: TimeInterval = ActivationResolver.holdThreshold) {
        self.holdThreshold = holdThreshold
    }

    /// - Parameters:
    ///   - isSessionActive: true while the controller is preparing or listening.
    mutating func resolve(
        event: HotkeyEvent,
        mode: ActivationMode,
        isSessionActive: Bool,
        at timestamp: Date
    ) -> Action {
        switch event {
        case .pressed:
            pressTimestamp = timestamp
            switch mode {
            case .auto:
                if isSessionActive {
                    startedOnCurrentPress = false
                    return .stop
                }
                startedOnCurrentPress = true
                return .start
            case .holdToTalk:
                if isSessionActive {
                    // Started some other way (menu bar, field mic): the key stops it.
                    startedOnCurrentPress = false
                    return .stop
                }
                startedOnCurrentPress = true
                return .start
            case .toggle:
                if isSessionActive {
                    startedOnCurrentPress = false
                    return .stop
                }
                startedOnCurrentPress = true
                return .start
            }

        case .released:
            let heldFor = pressTimestamp.map { timestamp.timeIntervalSince($0) } ?? 0
            let startedHere = startedOnCurrentPress
            pressTimestamp = nil
            startedOnCurrentPress = false
            switch mode {
            case .auto:
                // Tap (< threshold) leaves it listening; a real hold stops on release.
                guard startedHere, heldFor >= holdThreshold, isSessionActive else { return .none }
                return .stop
            case .holdToTalk:
                // Honour the release even if we are still preparing (model still loading).
                guard startedHere else { return .none }
                return .stop
            case .toggle:
                return .none
            }

        case .interrupted:
            // Only undo a session this very press started (or is about to start); an earlier
            // session is left alone. After a real hold the user is dictating, so a stray key
            // (Return to send, say) must not throw the recording away.
            guard startedOnCurrentPress else { return .none }
            let heldFor = pressTimestamp.map { timestamp.timeIntervalSince($0) } ?? 0
            guard heldFor < holdThreshold else { return .none }
            startedOnCurrentPress = false
            return .cancel
        }
    }

    /// Forgets any in-flight press (used when the session ends by other means).
    mutating func reset() {
        pressTimestamp = nil
        startedOnCurrentPress = false
    }
}

import ApplicationServices
import Foundation

/// When `FocusTracker` reads the focused element again. Pure state and rules, so they are unit
/// tested; the tracker owns the timer and the worker queue.
///
/// At most one read is in flight. Requests made meanwhile are folded into exactly one follow-up
/// read. Focus and window changes are read promptly (≤ 30 Hz); refreshes triggered by typing are
/// capped at 8 Hz, and typing in a single-line field triggers none, since it can't move the mic.
struct FocusRefreshPolicy {
    enum Urgency: Int, Comparable {
        /// The text or caret moved while typing: only the caret line of multi-line text changes.
        case typing
        /// Focus, the window, or the element itself changed.
        case prompt

        static func < (lhs: Urgency, rhs: Urgency) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// How an Accessibility notification from the frontmost app is handled.
    struct Response: Equatable {
        var notesTyping = false
        var refresh: Urgency?
        var windowFrameIsStale = false
        var focusedElementDestroyed = false
    }

    static let promptInterval: TimeInterval = 1.0 / 30
    static let typingInterval: TimeInterval = 1.0 / 8

    private(set) var isReadInFlight = false
    /// When the read that is already scheduled will run, if one is.
    private(set) var scheduledAt: TimeInterval?
    private var followUp: Urgency?
    private var lastReadStartedAt = -TimeInterval.greatestFiniteMagnitude

    static func minimumInterval(for urgency: Urgency) -> TimeInterval {
        urgency == .prompt ? promptInterval : typingInterval
    }

    /// Asks for a read. Returns when to schedule it, or nil when a read at least as early is
    /// already scheduled, or one is in flight (a single follow-up then runs after it).
    mutating func request(_ urgency: Urgency, now: TimeInterval) -> TimeInterval? {
        if isReadInFlight {
            followUp = max(followUp ?? urgency, urgency)
            return nil
        }
        let time = max(now, lastReadStartedAt + Self.minimumInterval(for: urgency))
        if let scheduledAt, scheduledAt <= time { return nil }
        scheduledAt = time
        return time
    }

    /// The scheduled time arrived (whether or not the read then starts), or it was cancelled.
    mutating func clearSchedule() {
        scheduledAt = nil
    }

    mutating func readStarted(now: TimeInterval) {
        scheduledAt = nil
        isReadInFlight = true
        lastReadStartedAt = now
    }

    /// The urgency of the one follow-up read to request, when anything asked during the read.
    mutating func readFinished() -> Urgency? {
        isReadInFlight = false
        defer { followUp = nil }
        return followUp
    }

    // MARK: - Notifications

    /// - Parameters:
    ///   - isFocusedElement: the notification is about the focused editable element.
    ///   - focusedIsMultiline: that element is multi-line text, where the mic follows the caret.
    static func response(to notification: String, isFocusedElement: Bool, focusedIsMultiline: Bool) -> Response {
        switch notification {
        case kAXUIElementDestroyedNotification:
            guard isFocusedElement else { return Response() }
            return Response(refresh: .prompt, focusedElementDestroyed: true)
        case kAXValueChangedNotification:
            // Other elements' values (clocks, progress…) change all the time; ignore them.
            guard isFocusedElement else { return Response() }
            return Response(notesTyping: true, refresh: focusedIsMultiline ? .typing : nil)
        case kAXSelectedTextChangedNotification:
            // A single-line field's mic ignores the caret; the poll covers anything else.
            if isFocusedElement, !focusedIsMultiline { return Response() }
            return Response(refresh: .typing)
        case kAXWindowMovedNotification, kAXWindowResizedNotification, kAXFocusedWindowChangedNotification:
            return Response(refresh: .prompt, windowFrameIsStale: true)
        default:
            return Response(refresh: .prompt)
        }
    }
}

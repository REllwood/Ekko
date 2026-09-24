import ApplicationServices
import XCTest
@testable import Ekko

final class FocusRefreshPolicyTests: XCTestCase {
    private typealias Policy = FocusRefreshPolicy

    // MARK: - Scheduling

    func testFirstRequestRunsImmediately() {
        var policy = Policy()
        XCTAssertEqual(policy.request(.prompt, now: 100), 100)
        XCTAssertEqual(policy.scheduledAt, 100)
    }

    func testRequestsAfterAReadAreRateLimitedByUrgency() {
        var policy = Policy()
        policy.readStarted(now: 100)
        XCTAssertNil(policy.readFinished())

        XCTAssertEqual(policy.request(.typing, now: 100.01)!, 100 + Policy.typingInterval, accuracy: 1e-9)
        // A prompt request moves the scheduled read earlier.
        XCTAssertEqual(policy.request(.prompt, now: 100.01)!, 100 + Policy.promptInterval, accuracy: 1e-9)
        // A typing request never delays or duplicates it.
        XCTAssertNil(policy.request(.typing, now: 100.02))
    }

    func testTypingRefreshesAreCappedAtEightPerSecond() {
        XCTAssertEqual(Policy.typingInterval, 1.0 / 8, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(Policy.promptInterval, Policy.typingInterval)

        var policy = Policy()
        var reads: [TimeInterval] = []
        // A notification every 10 ms for one second of typing.
        for step in 0..<100 {
            let now = Double(step) * 0.01
            if let at = policy.scheduledAt, at <= now {
                policy.readStarted(now: now)
                reads.append(now)
                _ = policy.readFinished()
            }
            _ = policy.request(.typing, now: now)
        }
        XCTAssertLessThanOrEqual(reads.count, 9)
        for (earlier, later) in zip(reads, reads.dropFirst()) {
            XCTAssertGreaterThanOrEqual(later - earlier, Policy.typingInterval - 1e-9)
        }
    }

    func testRequestsDuringAReadFoldIntoExactlyOneFollowUp() {
        var policy = Policy()
        _ = policy.request(.prompt, now: 0)
        policy.readStarted(now: 0)
        XCTAssertTrue(policy.isReadInFlight)

        XCTAssertNil(policy.request(.typing, now: 0.01))
        XCTAssertNil(policy.request(.prompt, now: 0.02))
        XCTAssertNil(policy.request(.typing, now: 0.03))
        XCTAssertNil(policy.scheduledAt)

        // The follow-up takes the most urgent request.
        XCTAssertEqual(policy.readFinished(), .prompt)
        XCTAssertFalse(policy.isReadInFlight)
        XCTAssertEqual(policy.request(.prompt, now: 0.2), 0.2)

        policy.readStarted(now: 0.2)
        XCTAssertNil(policy.readFinished(), "Nothing asked during this read, so nothing follows it")
    }

    func testTypingOnlyFollowUpStaysTypingUrgency() {
        var policy = Policy()
        policy.readStarted(now: 0)
        _ = policy.request(.typing, now: 0.01)
        XCTAssertEqual(policy.readFinished(), .typing)
    }

    func testClearedScheduleAcceptsANewRequest() {
        var policy = Policy()
        XCTAssertEqual(policy.request(.prompt, now: 5), 5)
        XCTAssertNil(policy.request(.prompt, now: 5))
        policy.clearSchedule()
        XCTAssertEqual(policy.request(.prompt, now: 5), 5)
    }

    // MARK: - Notifications

    private func response(
        _ notification: String,
        focused: Bool = true,
        multiline: Bool = false
    ) -> Policy.Response {
        Policy.response(to: notification, isFocusedElement: focused, focusedIsMultiline: multiline)
    }

    func testTypingInASingleLineFieldOnlyFlagsTyping() {
        XCTAssertEqual(response(kAXValueChangedNotification), Policy.Response(notesTyping: true))
        // Its caret doesn't affect placement either.
        XCTAssertEqual(response(kAXSelectedTextChangedNotification), Policy.Response())
    }

    func testTypingInMultilineTextRefreshesAtTypingRate() {
        XCTAssertEqual(
            response(kAXValueChangedNotification, multiline: true),
            Policy.Response(notesTyping: true, refresh: .typing)
        )
        XCTAssertEqual(response(kAXSelectedTextChangedNotification, multiline: true), Policy.Response(refresh: .typing))
    }

    func testOtherElementsValueChangesAreIgnored() {
        XCTAssertEqual(response(kAXValueChangedNotification, focused: false), Policy.Response())
        XCTAssertEqual(response(kAXValueChangedNotification, focused: false, multiline: true), Policy.Response())
    }

    func testSelectionChangesElsewhereRefreshAtTypingRate() {
        // e.g. Chromium posts them on the web area rather than the focused field.
        XCTAssertEqual(response(kAXSelectedTextChangedNotification, focused: false), Policy.Response(refresh: .typing))
    }

    func testFocusAndWindowChangesRefreshPromptly() {
        XCTAssertEqual(response(kAXFocusedUIElementChangedNotification, focused: false), Policy.Response(refresh: .prompt))
        for name in [kAXWindowMovedNotification, kAXWindowResizedNotification, kAXFocusedWindowChangedNotification] {
            XCTAssertEqual(response(name, focused: false), Policy.Response(refresh: .prompt, windowFrameIsStale: true), name)
        }
    }

    func testDestructionOfTheFocusedElement() {
        XCTAssertEqual(
            response(kAXUIElementDestroyedNotification),
            Policy.Response(refresh: .prompt, focusedElementDestroyed: true)
        )
        XCTAssertEqual(response(kAXUIElementDestroyedNotification, focused: false), Policy.Response())
    }
}

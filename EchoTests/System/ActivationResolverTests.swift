import XCTest
@testable import Echo

final class ActivationResolverTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000)

    private func at(_ offset: TimeInterval) -> Date {
        start.addingTimeInterval(offset)
    }

    // MARK: - Auto

    func testAutoTapStartsAndKeepsListening() {
        var resolver = ActivationResolver()
        XCTAssertEqual(resolver.resolve(event: .pressed, mode: .auto, isSessionActive: false, at: at(0)), .start)
        // Released after 120 ms -> a tap, so it stays listening.
        XCTAssertEqual(resolver.resolve(event: .released, mode: .auto, isSessionActive: true, at: at(0.12)), .none)
    }

    func testAutoSecondTapStops() {
        var resolver = ActivationResolver()
        _ = resolver.resolve(event: .pressed, mode: .auto, isSessionActive: false, at: at(0))
        _ = resolver.resolve(event: .released, mode: .auto, isSessionActive: true, at: at(0.1))
        XCTAssertEqual(resolver.resolve(event: .pressed, mode: .auto, isSessionActive: true, at: at(2)), .stop)
        XCTAssertEqual(resolver.resolve(event: .released, mode: .auto, isSessionActive: false, at: at(2.05)), .none)
    }

    func testAutoHoldStopsOnRelease() {
        var resolver = ActivationResolver()
        XCTAssertEqual(resolver.resolve(event: .pressed, mode: .auto, isSessionActive: false, at: at(0)), .start)
        XCTAssertEqual(resolver.resolve(event: .released, mode: .auto, isSessionActive: true, at: at(1.2)), .stop)
    }

    func testAutoHoldThresholdIsInclusive() {
        var resolver = ActivationResolver()
        _ = resolver.resolve(event: .pressed, mode: .auto, isSessionActive: false, at: at(0))
        XCTAssertEqual(
            resolver.resolve(event: .released, mode: .auto, isSessionActive: true, at: at(ActivationResolver.holdThreshold)),
            .stop
        )
    }

    func testAutoLongPressThatStoppedDoesNotStopTwice() {
        var resolver = ActivationResolver()
        // Session already running; a long press stops it, the release must not act again.
        XCTAssertEqual(resolver.resolve(event: .pressed, mode: .auto, isSessionActive: true, at: at(0)), .stop)
        XCTAssertEqual(resolver.resolve(event: .released, mode: .auto, isSessionActive: false, at: at(1.0)), .none)
    }

    // MARK: - Hold to talk

    func testHoldToTalk() {
        var resolver = ActivationResolver()
        XCTAssertEqual(resolver.resolve(event: .pressed, mode: .holdToTalk, isSessionActive: false, at: at(0)), .start)
        XCTAssertEqual(resolver.resolve(event: .released, mode: .holdToTalk, isSessionActive: true, at: at(0.05)), .stop)
    }

    func testHoldToTalkReleaseWhileStillPreparingStillStops() {
        var resolver = ActivationResolver()
        _ = resolver.resolve(event: .pressed, mode: .holdToTalk, isSessionActive: false, at: at(0))
        // Model still loading: the controller is not listening yet, but the release must count.
        XCTAssertEqual(resolver.resolve(event: .released, mode: .holdToTalk, isSessionActive: false, at: at(0.2)), .stop)
    }

    func testHoldToTalkKeyStopsASessionStartedElsewhere() {
        // Started from the menu bar or the field mic; the shortcut must still be able to stop it.
        var resolver = ActivationResolver()
        XCTAssertEqual(resolver.resolve(event: .pressed, mode: .holdToTalk, isSessionActive: true, at: at(0)), .stop)
        XCTAssertEqual(resolver.resolve(event: .released, mode: .holdToTalk, isSessionActive: false, at: at(0.2)), .none)
    }

    // MARK: - Toggle

    func testToggle() {
        var resolver = ActivationResolver()
        XCTAssertEqual(resolver.resolve(event: .pressed, mode: .toggle, isSessionActive: false, at: at(0)), .start)
        XCTAssertEqual(resolver.resolve(event: .released, mode: .toggle, isSessionActive: true, at: at(3)), .none)
        XCTAssertEqual(resolver.resolve(event: .pressed, mode: .toggle, isSessionActive: true, at: at(4)), .stop)
        XCTAssertEqual(resolver.resolve(event: .released, mode: .toggle, isSessionActive: false, at: at(4.9)), .none)
    }

    // MARK: - Misc

    func testStrayReleaseDoesNothing() {
        var resolver = ActivationResolver()
        XCTAssertEqual(resolver.resolve(event: .released, mode: .auto, isSessionActive: false, at: at(0)), .none)
        XCTAssertEqual(resolver.resolve(event: .released, mode: .holdToTalk, isSessionActive: true, at: at(0)), .none)
    }

    func testResetForgetsTheCurrentPress() {
        var resolver = ActivationResolver()
        _ = resolver.resolve(event: .pressed, mode: .auto, isSessionActive: false, at: at(0))
        resolver.reset()
        XCTAssertEqual(resolver.resolve(event: .released, mode: .auto, isSessionActive: true, at: at(2)), .none)
    }

    func testCustomHoldThreshold() {
        var resolver = ActivationResolver(holdThreshold: 1.0)
        _ = resolver.resolve(event: .pressed, mode: .auto, isSessionActive: false, at: at(0))
        XCTAssertEqual(resolver.resolve(event: .released, mode: .auto, isSessionActive: true, at: at(0.6)), .none)
    }

    // MARK: - Interrupted (the trigger modifier was used to type, e.g. ⌥3 for "#")

    func testInterruptCancelsSessionStartedByThisPress() {
        var resolver = ActivationResolver()
        XCTAssertEqual(resolver.resolve(event: .pressed, mode: .auto, isSessionActive: false, at: at(0)), .start)
        XCTAssertEqual(resolver.resolve(event: .interrupted, mode: .auto, isSessionActive: true, at: at(0.08)), .cancel)
        // The release that follows must not start or stop anything.
        XCTAssertEqual(resolver.resolve(event: .released, mode: .auto, isSessionActive: false, at: at(0.9)), .none)
    }

    func testInterruptInHoldToTalkCancelsAndIgnoresRelease() {
        var resolver = ActivationResolver()
        XCTAssertEqual(resolver.resolve(event: .pressed, mode: .holdToTalk, isSessionActive: false, at: at(0)), .start)
        XCTAssertEqual(resolver.resolve(event: .interrupted, mode: .holdToTalk, isSessionActive: true, at: at(0.3)), .cancel)
        XCTAssertEqual(resolver.resolve(event: .released, mode: .holdToTalk, isSessionActive: false, at: at(0.5)), .none)
    }

    func testInterruptDoesNotTouchAnEarlierSession() {
        var resolver = ActivationResolver()
        _ = resolver.resolve(event: .pressed, mode: .toggle, isSessionActive: false, at: at(0))
        _ = resolver.resolve(event: .released, mode: .toggle, isSessionActive: true, at: at(0.1))
        // Later, a stray interrupt with no press of ours in flight does nothing.
        XCTAssertEqual(resolver.resolve(event: .interrupted, mode: .toggle, isSessionActive: true, at: at(3)), .none)
    }

    func testInterruptOnlyFiresOncePerPress() {
        var resolver = ActivationResolver()
        _ = resolver.resolve(event: .pressed, mode: .auto, isSessionActive: false, at: at(0))
        XCTAssertEqual(resolver.resolve(event: .interrupted, mode: .auto, isSessionActive: true, at: at(0.1)), .cancel)
        XCTAssertEqual(resolver.resolve(event: .interrupted, mode: .auto, isSessionActive: false, at: at(0.2)), .none)
    }

    func testInterruptCancelsAPressThatHasNotStartedYet() {
        // Modifier-only triggers wait ~150 ms before starting; typing ⌥3 inside that window
        // must cancel the pending start even though no session is active yet.
        var resolver = ActivationResolver()
        XCTAssertEqual(resolver.resolve(event: .pressed, mode: .auto, isSessionActive: false, at: at(0)), .start)
        XCTAssertEqual(resolver.resolve(event: .interrupted, mode: .auto, isSessionActive: false, at: at(0.06)), .cancel)
    }

    func testKeyPressDuringALongHoldKeepsTheRecording() {
        var resolver = ActivationResolver()
        _ = resolver.resolve(event: .pressed, mode: .holdToTalk, isSessionActive: false, at: at(0))
        // Five seconds into push-to-talk the user bumps a key: keep dictating.
        XCTAssertEqual(resolver.resolve(event: .interrupted, mode: .holdToTalk, isSessionActive: true, at: at(5)), .none)
        XCTAssertEqual(resolver.resolve(event: .released, mode: .holdToTalk, isSessionActive: true, at: at(6)), .stop)
    }
}

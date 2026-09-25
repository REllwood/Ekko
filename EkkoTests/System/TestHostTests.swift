import AppKit
import XCTest
@testable import Ekko

/// The tests run inside Ekko.app. As a test host it must do nothing: no container (and so no
/// settings, event tap, permission prompts or model scan), no menu-bar item and no windows.
@MainActor
final class TestHostTests: XCTestCase {
    func testTheHostKnowsItIsHostingTests() {
        XCTAssertTrue(AppEnvironment.isHostingUnitTests)
    }

    func testTheHostBuiltNoContainer() throws {
        let delegate = try XCTUnwrap(NSApp.delegate as? AppDelegate, "Ekko's AppDelegate should be installed")
        XCTAssertNil(delegate.container, "The test host must not build AppContainer.shared")
    }

    func testTheHostShowsNoWindows() {
        // The menu-bar item, HUD, field mic and onboarding are all windows of some kind.
        XCTAssertTrue(NSApp.windows.filter(\.isVisible).isEmpty, "\(NSApp.windows.map(\.className))")
    }

    func testReopenAndTerminateAreSafeWithoutAContainer() throws {
        let delegate = try XCTUnwrap(NSApp.delegate as? AppDelegate)
        XCTAssertFalse(delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false))
        // Only the delegate callback; nothing actually terminates.
        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        XCTAssertNil(delegate.container)
    }
}

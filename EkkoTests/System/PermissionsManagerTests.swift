import XCTest
@testable import Ekko

/// `PermissionsManager` with scripted answers: the real TCC database is never read, and no
/// system prompt can appear.
@MainActor
final class PermissionsManagerTests: XCTestCase {
    func testStatusesComeFromTheSources() {
        let script = PermissionScript()
        script.microphone = .denied
        script.accessibilityTrusted = true
        let permissions = script.makeManager()
        XCTAssertEqual(permissions.microphone, .denied)
        XCTAssertEqual(permissions.accessibility, .granted)
        XCTAssertFalse(permissions.allGranted)
    }

    func testRefreshPicksUpChanges() {
        let script = PermissionScript()
        script.microphone = .notDetermined
        script.accessibilityTrusted = false
        let permissions = script.makeManager()
        XCTAssertEqual(permissions.accessibility, .denied)

        script.microphone = .granted
        script.accessibilityTrusted = true
        XCTAssertEqual(permissions.microphone, .notDetermined, "nothing changes until a refresh")
        permissions.refresh()
        XCTAssertEqual(permissions.microphone, .granted)
        XCTAssertEqual(permissions.accessibility, .granted)
        XCTAssertTrue(permissions.allGranted)
    }

    func testRequestingAnAlreadyGrantedMicrophoneDoesNotPrompt() async {
        let script = PermissionScript()
        script.microphone = .granted
        let permissions = script.makeManager()
        let status = await permissions.requestMicrophone()
        XCTAssertEqual(status, .granted)
        XCTAssertEqual(script.microphonePrompts, 0)
    }

    func testRequestingTheMicrophoneReturnsTheAnswer() async {
        let script = PermissionScript()
        script.microphone = .notDetermined
        script.answersMicrophonePrompt = false
        let permissions = script.makeManager()
        let status = await permissions.requestMicrophone()
        XCTAssertEqual(status, .denied)
        XCTAssertEqual(permissions.microphone, .denied)
        XCTAssertEqual(script.microphonePrompts, 1)
    }

    func testMonitoringStartsAndStopsOnce() {
        let permissions = PermissionScript().makeManager()
        XCTAssertFalse(permissions.isMonitoring)
        permissions.startMonitoring()
        permissions.startMonitoring()
        XCTAssertTrue(permissions.isMonitoring)
        permissions.stopMonitoring()
        XCTAssertFalse(permissions.isMonitoring)
        permissions.stopMonitoring()
        XCTAssertFalse(permissions.isMonitoring)
    }

    func testEveryPermissionLinksToItsSettingsPane() {
        for permission in Permission.allCases {
            XCTAssertFalse(permission.title.isEmpty)
            XCTAssertFalse(permission.why.isEmpty)
            let url = permission.settingsURL
            XCTAssertEqual(url?.scheme, "x-apple.systempreferences", "\(permission)")
            XCTAssertTrue(url?.absoluteString.contains("Privacy_") ?? false, "\(permission)")
        }
    }
}

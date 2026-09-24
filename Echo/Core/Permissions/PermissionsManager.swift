import AVFoundation
import AppKit
import ApplicationServices
import Foundation

enum PermissionStatus: Equatable, Sendable {
    case notDetermined
    case granted
    case denied
}

enum Permission: String, CaseIterable, Sendable {
    case microphone
    case accessibility

    var title: String {
        switch self {
        case .microphone: return "Microphone"
        case .accessibility: return "Accessibility"
        }
    }

    var why: String {
        switch self {
        case .microphone: return "To hear what you say. Audio never leaves this Mac."
        case .accessibility: return "To notice your shortcut and type into other apps."
        }
    }

    /// Deep link into the matching System Settings privacy pane.
    var settingsURL: URL? {
        switch self {
        case .microphone:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .accessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        }
    }
}

/// Tracks and requests the two permissions Echo needs.
/// `startMonitoring()` should poll Accessibility (there is no notification API) while the
/// app is frontmost/onboarding is open, and listen for AVCaptureDevice authorization changes.
@Observable
@MainActor
final class PermissionsManager {
    private(set) var microphone: PermissionStatus = .notDetermined
    private(set) var accessibility: PermissionStatus = .notDetermined

    var allGranted: Bool { microphone == .granted && accessibility == .granted }

    /// How often the Accessibility trust flag is re-read while monitoring.
    static let pollInterval: TimeInterval = 1.0

    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    @ObservationIgnored private(set) var isMonitoring = false

    init() {
        refresh()
    }

    deinit {
        pollTimer?.invalidate()
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
    }

    func refresh() {
        let newMicrophone = Self.microphoneStatus()
        let newAccessibility: PermissionStatus = AXIsProcessTrusted() ? .granted : .denied

        if newMicrophone != microphone {
            Log.permissions.info("Microphone permission \(String(describing: self.microphone), privacy: .public) -> \(String(describing: newMicrophone), privacy: .public)")
            microphone = newMicrophone
        }
        if newAccessibility != accessibility {
            Log.permissions.info("Accessibility permission \(String(describing: self.accessibility), privacy: .public) -> \(String(describing: newAccessibility), privacy: .public)")
            accessibility = newAccessibility
        }
    }

    /// Shows the system microphone prompt if needed. Returns the resulting status.
    @discardableResult
    func requestMicrophone() async -> PermissionStatus {
        if Self.microphoneStatus() == .granted {
            refresh()
            return microphone
        }
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        Log.permissions.info("Microphone request result: \(granted, privacy: .public)")
        refresh()
        return microphone
    }

    /// Shows the system Accessibility prompt (AXIsProcessTrustedWithOptions with prompt = true).
    func promptAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        Log.permissions.info("Accessibility prompt shown, trusted = \(trusted, privacy: .public)")
        refresh()
    }

    func openSystemSettings(for permission: Permission) {
        guard let url = permission.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// Begins polling/observing so `microphone`/`accessibility` stay current.
    /// There is no change notification for Accessibility trust, so it is polled once a second
    /// while monitoring is on, plus once whenever Echo becomes active.
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        refresh()

        let timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
        Log.permissions.debug("Permission monitoring started")
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        pollTimer?.invalidate()
        pollTimer = nil
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        Log.permissions.debug("Permission monitoring stopped")
    }

    // MARK: - Helpers

    static func microphoneStatus() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        case .denied, .restricted: return .denied
        @unknown default: return .denied
        }
    }
}

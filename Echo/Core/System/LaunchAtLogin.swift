import Foundation
import ServiceManagement

/// Wraps `SMAppService.mainApp` so the Settings UI can toggle "Open at login" and see what the
/// system actually did (registration can require user approval in System Settings).
@Observable
@MainActor
final class LaunchAtLogin {
    enum Status: Equatable, Sendable {
        case enabled
        case disabled
        case requiresApproval
        case unavailable

        var isEnabled: Bool { self == .enabled }
    }

    private(set) var status: Status = .disabled
    /// Last registration failure, for the Settings UI.
    private(set) var lastError: String?

    @ObservationIgnored private var isObserving = false

    init() {
        refresh()
    }

    func refresh() {
        switch SMAppService.mainApp.status {
        case .enabled: status = .enabled
        case .notRegistered: status = .disabled
        case .requiresApproval: status = .requiresApproval
        case .notFound: status = .unavailable
        @unknown default: status = .unavailable
        }
    }

    /// Registers or unregisters the app. Failures are recorded, never thrown.
    func apply(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled { try service.register() }
            } else {
                if service.status == .enabled || service.status == .requiresApproval {
                    try service.unregister()
                }
            }
            lastError = nil
            Log.app.info("Launch at login set to \(enabled, privacy: .public)")
        } catch {
            lastError = error.localizedDescription
            Log.app.error("Launch at login failed: \(error.localizedDescription, privacy: .public)")
        }
        refresh()
    }

    /// Applies `settings.launchAtLogin` now and whenever it changes.
    func startObserving(_ settings: SettingsStore) {
        guard !isObserving else { return }
        isObserving = true
        apply(settings.launchAtLogin)
        track(settings)
    }

    private func track(_ settings: SettingsStore) {
        withObservationTracking {
            _ = settings.launchAtLogin
        } onChange: { [weak self, weak settings] in
            Task { @MainActor [weak self, weak settings] in
                guard let self, let settings else { return }
                self.apply(settings.launchAtLogin)
                self.track(settings)
            }
        }
    }
}

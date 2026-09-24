import AppKit
import SwiftUI

/// Pages in the Settings window sidebar.
enum SettingsPage: String, CaseIterable, Identifiable {
    case general
    case dictation
    case models
    case languages
    case shortcut
    case permissions
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .dictation: return "Dictation"
        case .models: return "Models"
        case .languages: return "Languages"
        case .shortcut: return "Shortcut"
        case .permissions: return "Permissions"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .dictation: return "mic"
        case .models: return "cpu"
        case .languages: return "globe"
        case .shortcut: return "keyboard"
        case .permissions: return "lock.shield"
        case .about: return "info.circle"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "Startup, feedback, and your microphone."
        case .dictation: return "How Echo listens and how text arrives."
        case .models: return "Speech models installed on this Mac."
        case .languages: return "The language Echo expects to hear."
        case .shortcut: return "The key you press to start dictating."
        case .permissions: return "What Echo needs from macOS."
        case .about: return "Version and credits."
        }
    }
}

/// The single entry point the app delegate uses to attach the UI layer.
@MainActor
final class UICoordinator {
    private let container: AppContainer
    private let statusItem: StatusItemController
    private let hud: HUDController
    private let fieldMic: FieldMicController
    private var settingsWindow: SettingsWindowController?
    private var onboardingWindow: OnboardingWindowController?

    init(container: AppContainer) {
        self.container = container
        self.statusItem = StatusItemController(container: container)
        self.hud = HUDController(container: container)
        self.fieldMic = FieldMicController(container: container)
        statusItem.coordinator = self
    }

    // MARK: - Installation

    func installStatusItem() {
        statusItem.install()
        Log.ui.info("Status item installed")
    }

    func startHUD() {
        hud.start()
        Log.ui.info("HUD controller started")
    }

    /// The clickable mic that follows the focused text field in any app.
    func startFieldMic() {
        fieldMic.start()
    }

    // MARK: - Windows

    func showOnboarding(startingAt step: Int = 0, onFinished: @escaping () -> Void) {
        let controller = onboardingWindow ?? OnboardingWindowController(container: container, initialStep: step)
        onboardingWindow = controller
        var didContinue = false
        let continueOnce: () -> Void = { [weak self] in
            guard !didContinue else { return }
            didContinue = true
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
            onFinished()
        }
        controller.onFinished = continueOnce
        controller.onClosedEarly = continueOnce
        controller.show()
    }

    func showSettings(page: SettingsPage = .general) {
        let controller = settingsWindow ?? SettingsWindowController(container: container)
        settingsWindow = controller
        controller.show(page: page)
    }

    func showAbout() {
        showSettings(page: .about)
    }

    func showPopover() {
        statusItem.showPopover()
    }

    /// Closes the menu-bar popover if it is open (used before showing a window).
    func dismissPopover() {
        statusItem.closePopover()
    }
}

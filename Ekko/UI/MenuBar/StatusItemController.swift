import AppKit
import Observation
import SwiftUI

/// Owns the `NSStatusItem`: the animated template icon, the left-click popover and the
/// right-click menu.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    weak var coordinator: UICoordinator?

    private let container: AppContainer
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var animationTimer: Timer?
    private var frameIndex = 0
    private var displayedState: DictationState = .idle
    /// The app that was frontmost before the popover activated Ekko.
    private var previousApp: NSRunningApplication?

    init(container: AppContainer) {
        self.container = container
        super.init()
    }

    deinit {
        animationTimer?.invalidate()
    }

    // MARK: - Install

    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Ekko dictation")
            button.toolTip = "Ekko — press \(container.settings.hotkey.displayString) to dictate"
        }
        statusItem = item

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let hosting = NSHostingController(rootView: makeMenuBarView())
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting

        observeState()
        refreshState()
    }

    /// Opens the popover under the menu-bar icon (used by debug launch flags).
    func showPopover() {
        guard let button = statusItem?.button, !popover.isShown else { return }
        togglePopover(from: button)
    }

    func closePopover() {
        if popover.isShown { popover.performClose(nil) }
    }

    // MARK: - Popover content

    private func makeMenuBarView() -> MenuBarView {
        MenuBarView(
            container: container,
            openSettings: { [weak self] page in
                self?.previousApp = nil // Settings takes focus; don't bounce back to the old app.
                self?.closePopover()
                self?.coordinator?.showSettings(page: page)
            },
            toggleDictation: { [weak self] in
                self?.toggleDictationFromPopover()
            },
            quit: { NSApp.terminate(nil) }
        )
    }

    // MARK: - Clicks

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isSecondary = event?.type == .rightMouseUp
            || (event?.modifierFlags.contains(.control) ?? false)
        if isSecondary {
            showMenu()
        } else {
            togglePopover(from: sender)
        }
    }

    private func togglePopover(from button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            let frontmost = NSWorkspace.shared.frontmostApplication
            // Only remember a real other app; if Ekko is already in front there is nothing to return to.
            previousApp = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : frontmost
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showMenu() {
        closePopover()
        let menu = NSMenu()
        menu.autoenablesItems = false

        let isActive = container.dictation.state.isActive
        let toggleItem = NSMenuItem(
            title: isActive ? "Stop Dictation" : "Start Dictation",
            action: #selector(toggleDictation),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        if container.dictation.state.isListening {
            let cancelItem = NSMenuItem(title: "Cancel", action: #selector(cancelDictation), keyEquivalent: "")
            cancelItem.target = self
            menu.addItem(cancelItem)
        }

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let permissionsItem = NSMenuItem(title: "Check Permissions…", action: #selector(openPermissions), keyEquivalent: "")
        permissionsItem.target = self
        menu.addItem(permissionsItem)

        let aboutItem = NSMenuItem(title: "About Ekko", action: #selector(openAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Ekko", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    /// The popover activated Ekko, so the user's text field lost focus. Close the popover,
    /// give focus back to the app they came from, then start or stop once it is frontmost so
    /// focus capture and the final paste target the right window.
    private func toggleDictationFromPopover() {
        let target = previousApp
        previousApp = nil
        closePopover()
        if let target, !target.isTerminated {
            target.activate()
        } else {
            NSApp.deactivate()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.container.dictation.toggle()
        }
    }

    // MARK: - NSPopoverDelegate

    /// Opening the popover made Ekko the active app. If it was dismissed with Esc or a second
    /// click on the icon, Ekko would stay in front with no window, and the next dictation would
    /// paste into nothing. Hand focus back to the app the user came from.
    func popoverDidClose(_ notification: Notification) {
        guard let target = previousApp else { return }
        previousApp = nil
        guard NSApp.isActive, !target.isTerminated else { return }
        let hasOwnWindow = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain }
        guard !hasOwnWindow else { return } // Settings or onboarding was opened from the popover.
        target.activate()
    }

    @objc private func toggleDictation() { container.dictation.toggle() }
    @objc private func cancelDictation() { container.dictation.cancel() }
    @objc private func openSettings() { coordinator?.showSettings(page: .general) }
    @objc private func openPermissions() { coordinator?.showSettings(page: .permissions) }
    @objc private func openAbout() { coordinator?.showAbout() }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - State -> icon

    private func observeState() {
        withObservationTracking {
            _ = container.dictation.state
            _ = container.settings.hotkey
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.refreshState()
                self.observeState()
            }
        }
    }

    private func refreshState() {
        displayedState = container.dictation.state
        statusItem?.button?.toolTip = "Ekko — press \(container.settings.hotkey.displayString) to dictate"
        switch displayedState {
        case .listening, .transcribing, .preparing:
            startAnimating()
        default:
            stopAnimating()
        }
        updateIcon()
    }

    private func startAnimating() {
        guard animationTimer == nil else { return }
        let timer = Timer(
            timeInterval: 1.0 / 12.0,
            target: self,
            selector: #selector(advanceFrame),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    private func stopAnimating() {
        animationTimer?.invalidate()
        animationTimer = nil
        frameIndex = 0
    }

    @objc private func advanceFrame() {
        frameIndex = (frameIndex + 1) % StatusItemIcon.frameCount
        updateIcon()
    }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        switch displayedState {
        case .idle:
            button.image = StatusItemIcon.idle
        case .preparing, .transcribing:
            button.image = StatusItemIcon.transcribing(frame: frameIndex)
        case .listening:
            button.image = StatusItemIcon.listening(frame: frameIndex, level: container.audio.level)
        case .inserting:
            button.image = StatusItemIcon.symbol("checkmark")
        case .failed:
            button.image = StatusItemIcon.symbol("exclamationmark.triangle")
        }
        button.setAccessibilityLabel("Ekko — \(DictationPresentation.title(for: displayedState))")
    }
}

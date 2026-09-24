import AppKit
import ApplicationServices
import Observation
import SwiftUI

/// Shows and positions the dictation HUD. Observes `DictationController.state` and the
/// `showHUD` preference; the pill itself reads the live audio level directly.
@MainActor
final class HUDController {
    private let container: AppContainer
    private var panel: HUDPanel?
    private var hideTask: Task<Void, Never>?
    private var showTask: Task<Void, Never>?
    private var isVisible = false

    /// A session that is cancelled within this window (a hotkey used for typing) never shows the HUD.
    private let appearDelay: Double = 0.15

    /// How long the HUD lingers after returning to idle.
    private let lingerSeconds: Double = 0.6
    /// Gap between the pill and the bottom of the screen.
    private let bottomInset: CGFloat = 24

    init(container: AppContainer) {
        self.container = container
    }

    func start() {
        observe()
        sync()
    }

    func stop() {
        hideTask?.cancel()
        showTask?.cancel()
        showTask = nil
        hide()
    }

    // MARK: - Observation

    private func observe() {
        withObservationTracking {
            _ = container.dictation.state
            _ = container.settings.showHUD
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.sync()
                self.observe()
            }
        }
    }

    private func sync() {
        guard container.settings.showHUD else {
            hideTask?.cancel()
            hide()
            return
        }

        switch container.dictation.state {
        case .preparing, .listening:
            hideTask?.cancel()
            hideTask = nil
            if isVisible { show() } else { scheduleShow() }
        case .transcribing, .inserting, .failed:
            hideTask?.cancel()
            hideTask = nil
            showTask?.cancel()
            showTask = nil
            show()
        case .idle:
            showTask?.cancel()
            showTask = nil
            scheduleHide()
        }
    }

    private func scheduleShow() {
        guard showTask == nil else { return }
        let seconds = appearDelay
        showTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.showTask = nil
            guard self.container.settings.showHUD, self.container.dictation.state.isActive else { return }
            self.show()
        }
    }

    private func scheduleHide() {
        guard isVisible else { return }
        hideTask?.cancel()
        let seconds = lingerSeconds
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    // MARK: - Panel

    private func show() {
        // Already on screen: SwiftUI observation updates the pill in place. Rebuilding the
        // hosting view here would replay the entrance animation on every state change.
        guard !isVisible else { return }
        let panel = existingPanel()
        let hosting = NSHostingView(rootView: HUDView(container: container))
        hosting.frame = NSRect(origin: .zero, size: HUDView.panelSize)
        panel.contentView = hosting
        position(panel)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        isVisible = true
        Log.ui.debug("HUD shown")
    }

    private func hide() {
        guard isVisible, let panel else { isVisible = false; return }
        panel.orderOut(nil)
        panel.contentView = nil
        isVisible = false
        Log.ui.debug("HUD hidden")
    }

    private func existingPanel() -> HUDPanel {
        if let panel { return panel }
        let created = HUDPanel(size: HUDView.panelSize)
        panel = created
        return created
    }

    // MARK: - Positioning

    private func position(_ panel: HUDPanel) {
        let screen = targetScreen() ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = HUDView.panelSize
        // The pill sits inside a larger transparent panel; keep the pill `bottomInset` above
        // the bottom edge by accounting for the vertical padding around it.
        let verticalPadding = (size.height - HUDView.pillHeight) / 2
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.minY + bottomInset - verticalPadding
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
    }

    /// The screen showing the frontmost app's focused window, else the main screen.
    private func targetScreen() -> NSScreen? {
        guard AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return NSScreen.main
        }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowValue) == .success,
              let raw = windowValue,
              CFGetTypeID(raw) == AXUIElementGetTypeID() else {
            return NSScreen.main
        }
        // swiftlint:disable:next force_cast
        let window = raw as! AXUIElement

        guard let origin = axPoint(of: window, attribute: kAXPositionAttribute),
              let size = axSize(of: window, attribute: kAXSizeAttribute) else {
            return NSScreen.main
        }

        // AX uses a top-left origin anchored to the primary display.
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        let centre = CGPoint(
            x: origin.x + size.width / 2,
            y: primaryMaxY - (origin.y + size.height / 2)
        )
        return NSScreen.screens.first { $0.frame.contains(centre) } ?? NSScreen.main
    }

    private func axPoint(of element: AXUIElement, attribute: String) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let raw = value,
              CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        // swiftlint:disable:next force_cast
        var point = CGPoint.zero
        guard AXValueGetValue(raw as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    private func axSize(of element: AXUIElement, attribute: String) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let raw = value,
              CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(raw as! AXValue, .cgSize, &size) else { return nil }
        return size
    }
}

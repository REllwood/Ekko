import AppKit
import SwiftUI

/// The first-run window: 640 x 520, same chrome as Settings, not resizable.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    var onFinished: (() -> Void)?
    /// Called when the window is closed before the flow finished.
    var onClosedEarly: (() -> Void)?
    private var didFinish = false

    private let container: AppContainer
    private let initialStep: Int
    private var window: NSWindow?

    init(container: AppContainer, initialStep: Int = 0) {
        self.container = container
        self.initialStep = initialStep
        super.init()
    }

    func show() {
        let window = makeWindowIfNeeded()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        Log.ui.info("Onboarding shown")
    }

    func close() {
        window?.close()
        window = nil
    }

    private func makeWindowIfNeeded() -> NSWindow {
        if let window { return window }

        let created = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        created.title = "Welcome to Echo"
        created.titleVisibility = .hidden
        created.titlebarAppearsTransparent = true
        created.isMovableByWindowBackground = true
        created.backgroundColor = EchoColor.pageNS
        created.delegate = self
        created.isReleasedWhenClosed = false
        created.center()

        let root = OnboardingView(container: container, initialStep: initialStep) { [weak self] in
            guard let self else { return }
            self.didFinish = true
            self.container.settings.hasCompletedOnboarding = true
            self.onFinished?()
        }
        created.contentView = NSHostingView(rootView: root)

        window = created
        return created
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        if !didFinish {
            Log.ui.info("Onboarding closed before finishing")
            onClosedEarly?()
        }
    }
}

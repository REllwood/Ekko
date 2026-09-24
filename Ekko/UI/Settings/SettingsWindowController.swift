import AppKit
import SwiftUI

/// Which page the settings sidebar shows. Shared between the window controller and the view.
@Observable
@MainActor
final class SettingsNavigation {
    var page: SettingsPage = .general
}

/// The single Settings window: 760 x 540, hidden title, full-size content, frame remembered.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let container: AppContainer
    private let navigation = SettingsNavigation()
    private var window: NSWindow?

    init(container: AppContainer) {
        self.container = container
        super.init()
    }

    func show(page: SettingsPage) {
        navigation.page = page
        let window = makeWindowIfNeeded()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        Log.ui.info("Settings shown (\(page.rawValue, privacy: .public))")
    }

    func close() {
        window?.close()
    }

    private func makeWindowIfNeeded() -> NSWindow {
        if let window { return window }

        let created = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        created.title = "Ekko Settings"
        created.titleVisibility = .hidden
        created.titlebarAppearsTransparent = true
        created.isMovableByWindowBackground = true
        created.backgroundColor = EkkoColor.pageNS
        created.minSize = NSSize(width: 720, height: 480)
        created.delegate = self
        created.isReleasedWhenClosed = false
        created.setFrameAutosaveName("EkkoSettingsWindow")

        let root = SettingsView(container: container, navigation: navigation)
        let hosting = NSHostingView(rootView: root)
        created.contentView = hosting
        created.center()
        created.setFrameUsingName("EkkoSettingsWindow")

        window = created
        return created
    }

    func windowWillClose(_ notification: Notification) {
        Log.ui.debug("Settings closed")
    }
}

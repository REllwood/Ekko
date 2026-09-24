import AppKit

/// Borderless, non-activating floating panel that hosts the dictation HUD. It must never take
/// focus away from the app the user is dictating into.
final class HUDPanel: NSPanel {

    init(size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isMovableByWindowBackground = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        isReleasedWhenClosed = false
        setAccessibilityLabel("Ekko dictation status")
    }

    /// Never key, never main — the target app keeps its focus and caret.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

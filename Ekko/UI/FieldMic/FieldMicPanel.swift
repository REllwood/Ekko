import AppKit
import SwiftUI

/// Borderless, non-activating floating panel that holds the field mic. Clicking it must never
/// activate Ekko or take keyboard focus from the text field the transcript will be pasted into.
final class FieldMicPanel: NSPanel {

    init(size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        becomesKeyOnlyIfNeeded = true
        ignoresMouseEvents = false
        isMovableByWindowBackground = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        isReleasedWhenClosed = false
    }

    /// Never key, never main — the target app keeps its focus and caret.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Hosts `FieldMicView` and handles the pointer itself, so a single click works on a panel that
/// never becomes key in an app that is never active: first mouse is accepted, hover is tracked
/// with an always-active tracking area, and only the button's circle responds.
final class FieldMicHostingView: NSHostingView<FieldMicView> {
    /// Radius around the centre that counts as the button.
    var hitRadius: CGFloat = 15
    var onHover: ((Bool) -> Void)?
    var onPress: ((Bool) -> Void)?
    var onClick: (() -> Void)?

    private var hoverArea: NSTrackingArea?
    /// A press that began as a single click; the later clicks of a double-click are ignored.
    private var isTrackingPress = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return isOnButton(local, slack: 0) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHover?(false)
    }

    override func mouseDown(with event: NSEvent) {
        // Only the first click of a double-click acts: the second would stop the dictation the
        // first just started. (0 comes from some synthesized clicks.)
        guard event.clickCount <= 1 else { return }
        isTrackingPress = true
        onPress?(true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isTrackingPress else { return }
        onPress?(isOnButton(convert(event.locationInWindow, from: nil), slack: 4))
    }

    override func mouseUp(with event: NSEvent) {
        guard isTrackingPress else { return }
        isTrackingPress = false
        onPress?(false)
        // Released off the button cancels, like any other button.
        if isOnButton(convert(event.locationInWindow, from: nil), slack: 4) {
            onClick?()
        }
    }

    private func isOnButton(_ point: NSPoint, slack: CGFloat) -> Bool {
        hypot(point.x - bounds.midX, point.y - bounds.midY) <= hitRadius + slack
    }
}

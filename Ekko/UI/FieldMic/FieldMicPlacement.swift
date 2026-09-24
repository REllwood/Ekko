import CoreGraphics

/// Where the field mic's button sits relative to the focused element. Pure geometry in AppKit
/// global coordinates (origin bottom-left of the primary display, y up), so every rule is tested.
enum FieldMicPlacement {
    struct Screen: Equatable {
        var frame: CGRect
        /// Excludes the menu bar and Dock; the button always stays inside it.
        var visibleFrame: CGRect
    }

    /// Gap between a single-line field's trailing edge and the button.
    static let outsideGap: CGFloat = 6
    /// Padding when the button has to sit inside a single-line field's trailing edge.
    static let insidePadding: CGFloat = 6
    /// Inset from the trailing edge (and, without a caret, the bottom) of multi-line text.
    static let cornerInset: CGFloat = 8
    /// Elements bigger than this share of the screen (full-window editors) use the multi-line rules.
    static let largeElementFraction: CGFloat = 0.6

    /// The screen holding the caret (multi-line) or the visible part of the element, else the one
    /// overlapping the element most. nil when the element is on no screen at all.
    static func screen(for target: EditableTarget, in screens: [Screen]) -> Screen? {
        var anchor = target.elementFrame
        if let window = target.windowFrame, window.intersects(anchor) {
            anchor = anchor.intersection(window)
        }
        if target.isMultiline, let caret = target.caretRect { anchor = caret }
        let centre = CGPoint(x: anchor.midX, y: anchor.midY)
        if let match = screens.first(where: { $0.frame.contains(centre) }) { return match }

        let overlaps = screens.map { ($0, area($0.frame.intersection(target.elementFrame))) }
        guard let best = overlaps.max(by: { $0.1 < $1.1 }), best.1 > 0 else { return nil }
        return best.0
    }

    static func buttonOrigin(for target: EditableTarget, on screen: Screen, buttonSize: CGSize) -> CGPoint? {
        buttonOrigin(
            elementFrame: target.elementFrame,
            caretRect: target.caretRect,
            windowFrame: target.windowFrame,
            isMultiline: target.isMultiline,
            visibleFrame: screen.visibleFrame,
            buttonSize: buttonSize
        )
    }

    /// Origin of the button, or nil when no part of the element is visible on this screen.
    static func buttonOrigin(
        elementFrame: CGRect,
        caretRect: CGRect?,
        windowFrame: CGRect?,
        isMultiline: Bool,
        visibleFrame: CGRect,
        buttonSize: CGSize
    ) -> CGPoint? {
        guard elementFrame.width > 0, elementFrame.height > 0,
              visibleFrame.width > 0, visibleFrame.height > 0 else { return nil }

        // A window that doesn't overlap the element is stale or belongs to a popover's parent.
        let window = windowFrame.flatMap { $0.width > 0 && $0.height > 0 && $0.intersects(elementFrame) ? $0 : nil }
        var shown = window.map { elementFrame.intersection($0) } ?? elementFrame
        shown = shown.intersection(visibleFrame)
        guard !shown.isNull, shown.width > 0, shown.height > 0 else { return nil }

        let isLarge = area(elementFrame) > largeElementFraction * area(visibleFrame)
        let origin = isMultiline || isLarge
            ? multilineOrigin(shown: shown, caret: caretRect, size: buttonSize)
            : singleLineOrigin(element: elementFrame, shown: shown, window: window, visibleFrame: visibleFrame, size: buttonSize)
        return CGPoint(
            x: clamp(origin.x, visibleFrame.minX, visibleFrame.maxX - buttonSize.width),
            y: clamp(origin.y, visibleFrame.minY, visibleFrame.maxY - buttonSize.height)
        )
    }

    /// Just outside the trailing edge, vertically centred; inside the trailing edge when outside
    /// would leave the screen or the window (or the trailing edge itself is cut off).
    private static func singleLineOrigin(
        element: CGRect,
        shown: CGRect,
        window: CGRect?,
        visibleFrame: CGRect,
        size: CGSize
    ) -> CGPoint {
        let y = shown.midY - size.height / 2
        let outsideX = element.maxX + outsideGap
        let limit = min(visibleFrame.maxX, window?.maxX ?? .greatestFiniteMagnitude)
        let trailingEdgeVisible = shown.maxX >= element.maxX - 0.5
        if trailingEdgeVisible, outsideX + size.width <= limit {
            return CGPoint(x: outsideX, y: y)
        }
        return CGPoint(x: shown.maxX - insidePadding - size.width, y: y)
    }

    /// In the trailing margin, level with the caret's line, so it follows the line being written
    /// without ever covering the text right after the caret (which a caret-hugging button would,
    /// and which would also swallow clicks meant for that text). Without a visible caret, the
    /// bottom-trailing corner of what's visible.
    private static func multilineOrigin(shown: CGRect, caret: CGRect?, size: CGSize) -> CGPoint {
        let x = shown.maxX - cornerInset - size.width
        if let caret, caret.midY >= shown.minY, caret.midY <= shown.maxY {
            return CGPoint(x: x, y: clamp(caret.midY - size.height / 2, shown.minY, shown.maxY - size.height))
        }
        return CGPoint(x: x, y: shown.minY + cornerInset)
    }

    /// Clamps into [lower, upper]; when the range is inverted (too small to fit), prefers `lower`.
    static func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        guard upper >= lower else { return lower }
        return min(max(value, lower), upper)
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }
}

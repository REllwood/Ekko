import AppKit
import ApplicationServices
import Foundation

/// Stateless, time-boxed Accessibility reads about one focused element, used by `FocusTracker`'s
/// worker queue. Never call these on the main thread: each read is blocking IPC to another app.
/// Results are in AX coordinates (top-left of the primary display, y down) unless noted.
/// Every call is guarded: a missing attribute means "unknown", never a crash.
enum FocusElementReader {
    /// Short so a hung app can't hold up the reads that follow for long.
    static let messagingTimeout: Float = 0.2

    enum Outcome<Value> {
        case value(Value)
        /// No such value (nothing focused, attribute missing, not editable, zero-size…).
        case missing
        /// The element no longer exists (`kAXErrorInvalidUIElement`).
        case gone
        /// The app did not answer in time (`kAXErrorCannotComplete`).
        case busy
    }

    struct Classification {
        var role: String?
        var isEditable: Bool
    }

    // MARK: - Focus and classification

    static func focusedElement(of app: AXUIElement) -> Outcome<AXUIElement> {
        let (raw, error) = copyValue(app, kAXFocusedUIElementAttribute)
        if error == .cannotComplete { return .busy }
        guard let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return .missing }
        let element = raw as! AXUIElement
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return .value(element)
    }

    /// Role and editability. Settability is only queried when the role alone doesn't decide.
    /// `.busy` when the app times out, so a slow answer is retried rather than cached as "not editable".
    static func classify(_ element: AXUIElement, app: FocusTargetRules.AppKind) -> Outcome<Classification> {
        let (roleValue, roleError) = copyValue(element, kAXRoleAttribute)
        if roleError == .cannotComplete { return .busy }
        if roleError == .invalidUIElement { return .gone }
        let role = roleValue as? String
        let subrole = copyValue(element, kAXSubroleAttribute).value as? String

        var traits = FocusTargetRules.Traits(role: role, subrole: subrole, app: app)
        if FocusTargetRules.roleDecision(role: role, subrole: subrole, app: app) == nil {
            guard let valueSettable = settable(element, kAXValueAttribute) else { return .busy }
            traits.isValueSettable = valueSettable
            if FocusTargetRules.isTextRole(role: role, subrole: subrole) {
                // One settable attribute is enough, and the (possibly long) value is never copied.
                if !valueSettable {
                    guard let selectionSettable = settable(element, kAXSelectedTextAttribute) else { return .busy }
                    traits.isSelectedTextSettable = selectionSettable
                }
                if !valueSettable, !traits.isSelectedTextSettable, app == .chromium {
                    guard let rangeSettable = settable(element, kAXSelectedTextRangeAttribute) else { return .busy }
                    traits.isSelectedTextRangeSettable = rangeSettable
                }
            } else {
                traits.valueIsString = valueSettable && copyValue(element, kAXValueAttribute).value is String
                guard let selectionSettable = settable(element, kAXSelectedTextAttribute) else { return .busy }
                traits.isSelectedTextSettable = selectionSettable
            }
        }
        return .value(Classification(role: role, isEditable: FocusTargetRules.isEditable(traits)))
    }

    // MARK: - Geometry

    static func frame(of element: AXUIElement) -> Outcome<CGRect> {
        let (position, error) = copyValue(element, kAXPositionAttribute)
        if error == .invalidUIElement { return .gone }
        if error == .cannotComplete { return .busy }
        guard let origin = Self.point(position),
              let size = Self.size(copyValue(element, kAXSizeAttribute).value),
              size.width >= 1, size.height >= 1 else { return .missing }
        return .value(CGRect(origin: origin, size: size))
    }

    /// Insertion point. Zero-length ranges often come back empty, so fall back to the character
    /// before the caret (its trailing edge) or, at the very start, the first character.
    /// A selection is anchored at its end, where the dictated text will finish.
    static func caretRect(of element: AXUIElement, elementFrame: CGRect) -> CGRect? {
        guard let range = FocusContextReader.selectedRange(element) else { return nil }
        let usable = { FocusTargetRules.usableCaret($0, elementFrame: elementFrame) }
        let end = range.location + range.length
        if range.length == 0, let rect = usable(bounds(of: element, location: range.location, length: 0)) {
            return rect
        }
        if end > 0, let rect = usable(bounds(of: element, location: end - 1, length: 1)) {
            return FocusTargetRules.trailingEdge(of: rect)
        }
        if end == 0, let rect = usable(bounds(of: element, location: 0, length: 1)) {
            return FocusTargetRules.leadingEdge(of: rect)
        }
        return nil
    }

    /// Frame of the element's window, else the app's focused window.
    static func windowFrame(of element: AXUIElement, app: AXUIElement) -> CGRect? {
        var window = copyValue(element, kAXWindowAttribute).value
        if window.map({ CFGetTypeID($0) != AXUIElementGetTypeID() }) ?? true {
            window = copyValue(app, kAXFocusedWindowAttribute).value
        }
        guard let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        let windowElement = window as! AXUIElement
        AXUIElementSetMessagingTimeout(windowElement, messagingTimeout)
        guard case .value(let frame) = frame(of: windowElement) else { return nil }
        return frame
    }

    /// Cheap typing signal for apps that don't post value-changed notifications.
    static func characterCount(of element: AXUIElement) -> Int? {
        copyValue(element, kAXNumberOfCharactersAttribute).value as? Int
    }

    // MARK: - Helpers

    /// Like `FocusContextReader.isSettable`, but nil when the app did not answer in time.
    private static func settable(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var settable: DarwinBoolean = false
        let error = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
        if error == .cannotComplete { return nil }
        return error == .success && settable.boolValue
    }

    private static func bounds(of element: AXUIElement, location: Int, length: Int) -> CGRect? {
        var range = CFRange(location: location, length: length)
        guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
        var value: CFTypeRef?
        let attribute = kAXBoundsForRangeParameterizedAttribute as CFString
        guard AXUIElementCopyParameterizedAttributeValue(element, attribute, parameter, &value) == .success else { return nil }
        return rect(value)
    }

    private static func copyValue(_ element: AXUIElement, _ attribute: String) -> (value: CFTypeRef?, error: AXError) {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return (error == .success ? value : nil, error)
    }

    private static func axValue(_ value: CFTypeRef?, _ type: AXValueType) -> AXValue? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        return AXValueGetType(axValue) == type ? axValue : nil
    }

    private static func point(_ value: CFTypeRef?) -> CGPoint? {
        var point = CGPoint.zero
        guard let axValue = axValue(value, .cgPoint), AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    private static func size(_ value: CFTypeRef?) -> CGSize? {
        var size = CGSize.zero
        guard let axValue = axValue(value, .cgSize), AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }

    private static func rect(_ value: CFTypeRef?) -> CGRect? {
        var rect = CGRect.zero
        guard let axValue = axValue(value, .cgRect), AXValueGetValue(axValue, .cgRect, &rect) else { return nil }
        return rect
    }
}

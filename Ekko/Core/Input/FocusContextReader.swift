import AppKit
import ApplicationServices
import Foundation

/// Thin, defensive wrapper around the Accessibility API used to read what the user is focused on.
/// Every call is guarded, time-boxed and non-throwing: a missing attribute simply means "unknown".
@MainActor
enum FocusContextReader {
    /// AX calls block the caller; keep them short so the hotkey path never stalls.
    nonisolated static let messagingTimeout: Float = 0.25
    /// How much text before the caret we keep for smart spacing/capitalization.
    static let contextCharacterLimit = 64

    /// Frontmost app + focused element, as far as the AX API will tell us.
    static func capture() -> FocusContext {
        var context = FocusContext()
        if let app = NSWorkspace.shared.frontmostApplication {
            context.appBundleID = app.bundleIdentifier
            context.appName = app.localizedName
            context.appPID = app.processIdentifier
        }
        guard AXIsProcessTrusted() else { return context }
        guard let element = focusedElement() else { return context }

        let role = string(element, kAXRoleAttribute)
        let subrole = string(element, kAXSubroleAttribute)
        context.elementRole = role
        context.isSecureField = subrole == (kAXSecureTextFieldSubrole as String)
            || (role == (kAXTextFieldRole as String) && subrole?.contains("Secure") == true)
        context.supportsAXInsertion = isSettable(element, kAXSelectedTextAttribute)

        guard !context.isSecureField else { return context }

        let value = string(element, kAXValueAttribute)
        if let value {
            context.isFieldEmpty = value.isEmpty
        }
        let range = selectedRange(element)
        if let selected = string(element, kAXSelectedTextAttribute), !selected.isEmpty {
            context.selectedText = selected
        } else if let value, let range, range.length > 0 {
            context.selectedText = substring(of: value, location: range.location, length: range.length)
        }
        if let value {
            if let range {
                context.textBeforeCursor = tail(of: value, endingAtUTF16Offset: range.location)
            } else if value.isEmpty {
                context.textBeforeCursor = ""
            }
        }
        return context
    }

    /// The element the system says has keyboard focus right now.
    nonisolated static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, messagingTimeout)
        var focused: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused)
        guard result == .success, let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return element
    }

    nonisolated static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    nonisolated static func selectedRange(_ element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        guard range.location >= 0, range.length >= 0 else { return nil }
        return range
    }

    nonisolated static func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success else { return false }
        return settable.boolValue
    }

    @discardableResult
    static func setSelectedText(_ element: AXUIElement, _ text: String) -> Bool {
        AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success
    }

    // MARK: - UTF-16 helpers (AX ranges are UTF-16 offsets)

    /// Up to `contextCharacterLimit` characters ending at `offset`.
    static func tail(of value: String, endingAtUTF16Offset offset: Int) -> String? {
        let units = Array(value.utf16)
        guard offset >= 0 else { return nil }
        let end = min(offset, units.count)
        let start = max(0, end - contextCharacterLimit)
        guard end >= start else { return nil }
        return String(utf16CodeUnits: Array(units[start..<end]), count: end - start)
    }

    static func substring(of value: String, location: Int, length: Int) -> String? {
        let units = Array(value.utf16)
        guard location >= 0, length > 0, location < units.count else { return nil }
        let end = min(location + length, units.count)
        return String(utf16CodeUnits: Array(units[location..<end]), count: end - location)
    }
}

import Foundation
import AppKit
import Carbon.HIToolbox

/// Modifier keys that can act as a standalone dictation trigger.
enum ModifierKey: String, Codable, CaseIterable, Sendable {
    case fn
    case rightOption
    case leftOption
    case rightCommand
    case rightControl
    case rightShift

    var keyCode: UInt16 {
        switch self {
        case .fn: return 63
        case .rightOption: return 61
        case .leftOption: return 58
        case .rightCommand: return 54
        case .rightControl: return 62
        case .rightShift: return 60
        }
    }

    /// The flag this key contributes to `NSEvent.modifierFlags`.
    var flag: NSEvent.ModifierFlags {
        switch self {
        case .fn: return .function
        case .rightOption, .leftOption: return .option
        case .rightCommand: return .command
        case .rightControl: return .control
        case .rightShift: return .shift
        }
    }

    var displayName: String {
        switch self {
        case .fn: return "Fn / Globe"
        case .rightOption: return "Right Option"
        case .leftOption: return "Left Option"
        case .rightCommand: return "Right Command"
        case .rightControl: return "Right Control"
        case .rightShift: return "Right Shift"
        }
    }

    var symbol: String {
        switch self {
        case .fn: return "🌐"
        case .rightOption, .leftOption: return "⌥"
        case .rightCommand: return "⌘"
        case .rightControl: return "⌃"
        case .rightShift: return "⇧"
        }
    }

    static func from(keyCode: UInt16) -> ModifierKey? {
        allCases.first { $0.keyCode == keyCode }
    }
}

/// A user-configurable trigger. Fixed contract.
struct Hotkey: Codable, Hashable, Sendable {
    enum Kind: Codable, Hashable, Sendable {
        /// A single modifier key pressed on its own (e.g. hold Right Option).
        case modifier(ModifierKey)
        /// A regular key plus modifiers (e.g. ⌥ Space). `modifiers` is `NSEvent.ModifierFlags.rawValue`
        /// masked to device-independent flags.
        case combo(keyCode: UInt16, modifiers: UInt)
    }

    var kind: Kind

    static let `default` = Hotkey(kind: .modifier(.rightOption))

    /// e.g. "Right ⌥" or "⌥ Space"
    var displayString: String {
        switch kind {
        case .modifier(let key):
            switch key {
            case .fn: return "Fn"
            case .rightOption: return "Right ⌥"
            case .leftOption: return "Left ⌥"
            case .rightCommand: return "Right ⌘"
            case .rightControl: return "Right ⌃"
            case .rightShift: return "Right ⇧"
            }
        case .combo(let keyCode, let modifiers):
            let flags = NSEvent.ModifierFlags(rawValue: modifiers)
            var parts: [String] = []
            if flags.contains(.control) { parts.append("⌃") }
            if flags.contains(.option) { parts.append("⌥") }
            if flags.contains(.shift) { parts.append("⇧") }
            if flags.contains(.command) { parts.append("⌘") }
            if flags.contains(.function) { parts.append("Fn") }
            parts.append(KeyCodeNames.name(for: keyCode))
            return parts.joined(separator: " ")
        }
    }

    var isModifierOnly: Bool {
        if case .modifier = kind { return true }
        return false
    }
}

/// How the trigger key behaves: tap to toggle, hold to talk, or both.
enum ActivationMode: String, Codable, CaseIterable, Sendable {
    /// Tap to toggle, or hold to talk — decided by how long the key is held (0.5 s threshold).
    case auto
    case holdToTalk
    case toggle

    var title: String {
        switch self {
        case .auto: return "Smart (tap or hold)"
        case .holdToTalk: return "Hold to talk"
        case .toggle: return "Press to start, press to stop"
        }
    }

    var detail: String {
        switch self {
        case .auto: return "Tap once to start and again to stop, or hold the key while you speak."
        case .holdToTalk: return "Echo listens only while the key is held down."
        case .toggle: return "Press once to start listening, press again to finish."
        }
    }
}

/// Human names for virtual key codes (US layout for letters/digits; symbols for special keys).
enum KeyCodeNames {
    static func name(for keyCode: UInt16) -> String {
        if let special = special[keyCode] { return special }
        if let layoutName = layoutName(for: keyCode) { return layoutName.uppercased() }
        return "Key \(keyCode)"
    }

    private static let special: [UInt16: String] = [
        UInt16(kVK_Space): "Space", UInt16(kVK_Return): "↩", UInt16(kVK_Tab): "⇥",
        UInt16(kVK_Delete): "⌫", UInt16(kVK_ForwardDelete): "⌦", UInt16(kVK_Escape): "⎋",
        UInt16(kVK_LeftArrow): "←", UInt16(kVK_RightArrow): "→", UInt16(kVK_UpArrow): "↑",
        UInt16(kVK_DownArrow): "↓", UInt16(kVK_Home): "↖", UInt16(kVK_End): "↘",
        UInt16(kVK_PageUp): "⇞", UInt16(kVK_PageDown): "⇟", UInt16(kVK_CapsLock): "⇪",
        UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3", UInt16(kVK_F4): "F4",
        UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6", UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8",
        UInt16(kVK_F9): "F9", UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12",
        UInt16(kVK_F13): "F13", UInt16(kVK_F14): "F14", UInt16(kVK_F15): "F15", UInt16(kVK_F16): "F16",
        UInt16(kVK_F17): "F17", UInt16(kVK_F18): "F18", UInt16(kVK_F19): "F19", UInt16(kVK_F20): "F20",
        UInt16(kVK_ANSI_KeypadEnter): "⌤", UInt16(kVK_ANSI_KeypadClear): "⌧",
    ]

    /// Resolves a printable character from the current keyboard layout.
    private static func layoutName(for keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = layoutData.withUnsafeBytes { bytes -> OSStatus in
            guard let base = bytes.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(
                base, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, chars.count, &length, &chars
            )
        }
        guard status == noErr, length > 0 else { return nil }
        let text = String(utf16CodeUnits: chars, count: length)
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }
}

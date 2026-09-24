import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Ekko

final class HotkeyTests: XCTestCase {
    private func roundTrip(_ hotkey: Hotkey) throws -> Hotkey {
        let data = try JSONEncoder().encode(hotkey)
        return try JSONDecoder().decode(Hotkey.self, from: data)
    }

    func testModifierHotkeyRoundTrip() throws {
        for key in ModifierKey.allCases {
            let hotkey = Hotkey(kind: .modifier(key))
            XCTAssertEqual(try roundTrip(hotkey), hotkey, "\(key)")
        }
    }

    func testComboHotkeyRoundTrip() throws {
        let modifiers = NSEvent.ModifierFlags([.option, .command]).rawValue
        let hotkey = Hotkey(kind: .combo(keyCode: UInt16(kVK_Space), modifiers: modifiers))
        let decoded = try roundTrip(hotkey)
        XCTAssertEqual(decoded, hotkey)
        guard case .combo(let keyCode, let decodedModifiers) = decoded.kind else {
            return XCTFail("expected a combo")
        }
        XCTAssertEqual(keyCode, UInt16(kVK_Space))
        XCTAssertEqual(decodedModifiers, modifiers)
    }

    func testDefaultHotkeyRoundTrip() throws {
        XCTAssertEqual(try roundTrip(.default), .default)
        XCTAssertEqual(Hotkey.default.kind, .modifier(.rightOption))
    }

    func testModifierDisplayStrings() {
        let expected: [ModifierKey: String] = [
            .fn: "Fn",
            .rightOption: "Right ⌥",
            .leftOption: "Left ⌥",
            .rightCommand: "Right ⌘",
            .rightControl: "Right ⌃",
            .rightShift: "Right ⇧",
        ]
        for (key, string) in expected {
            XCTAssertEqual(Hotkey(kind: .modifier(key)).displayString, string)
        }
    }

    func testComboDisplayStrings() {
        let cases: [(NSEvent.ModifierFlags, Int, String)] = [
            ([.option], kVK_Space, "⌥ Space"),
            ([.option, .command], kVK_Space, "⌥ ⌘ Space"),
            ([.control, .shift], kVK_Escape, "⌃ ⇧ ⎋"),
            ([.command], kVK_Return, "⌘ ↩"),
        ]
        for (flags, keyCode, expected) in cases {
            let hotkey = Hotkey(kind: .combo(keyCode: UInt16(keyCode), modifiers: flags.rawValue))
            XCTAssertEqual(hotkey.displayString, expected)
        }
    }

    func testIsModifierOnly() {
        XCTAssertTrue(Hotkey(kind: .modifier(.fn)).isModifierOnly)
        XCTAssertFalse(Hotkey(kind: .combo(keyCode: 49, modifiers: 0)).isModifierOnly)
    }

    func testModifierKeyCodesAndLookup() {
        let expected: [ModifierKey: UInt16] = [
            .fn: 63, .rightOption: 61, .leftOption: 58,
            .rightCommand: 54, .rightControl: 62, .rightShift: 60,
        ]
        for (key, code) in expected {
            XCTAssertEqual(key.keyCode, code)
            XCTAssertEqual(ModifierKey.from(keyCode: code), key)
        }
        XCTAssertNil(ModifierKey.from(keyCode: 0))
    }

    func testModifierKeyDeviceFlagsDistinguishLeftAndRight() {
        // Both option keys report the same device-independent flag, so the device bit decides.
        let rightOptionFlags = CGEventFlags(rawValue: ModifierKey.rightOption.deviceFlagMask)
            .union(.maskAlternate)
        XCTAssertTrue(ModifierKey.rightOption.isDown(flags: [.option], rawFlags: rightOptionFlags))
        XCTAssertFalse(ModifierKey.leftOption.isDown(flags: [.option], rawFlags: rightOptionFlags))
        // Fn has no device bit and falls back to the flag.
        XCTAssertTrue(ModifierKey.fn.isDown(flags: [.function], rawFlags: .maskSecondaryFn))
        XCTAssertFalse(ModifierKey.fn.isDown(flags: [], rawFlags: []))
    }

    func testDecodingGarbageFails() {
        let data = Data(#"{"kind":{"nonsense":{}}}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Hotkey.self, from: data))
    }
}

import AppKit
import Carbon.HIToolbox
import CoreGraphics
import XCTest
@testable import Ekko

/// Drives `HotkeyManager.handle(type:event:)` with synthetic events, exactly as the event tap
/// would, without installing a tap or needing Accessibility.
@MainActor
final class HotkeyManagerTests: XCTestCase {
    /// Everything the manager reported.
    private final class Recorder {
        var events: [HotkeyEvent] = []
        var escapes = 0
        var captures: [Hotkey?] = []
    }

    private func makeManager(_ hotkey: Hotkey = .default) -> (HotkeyManager, Recorder) {
        let manager = HotkeyManager()
        let recorder = Recorder()
        manager.hotkey = hotkey
        manager.onEvent = { recorder.events.append($0) }
        manager.onEscape = { recorder.escapes += 1 }
        return (manager, recorder)
    }

    private func beginCapture(on manager: HotkeyManager, recorder: Recorder) {
        manager.beginCapture { recorder.captures.append($0) }
    }

    // MARK: - Synthetic events

    private static let deviceLeftCommand: UInt64 = 0x0000_0008

    /// Flags as macOS reports them while `keys` are held: the shared flag plus each key's
    /// device-dependent bit.
    private func held(_ keys: ModifierKey...) -> CGEventFlags {
        keys.reduce(into: CGEventFlags()) { flags, key in
            flags.insert(CGEventFlags(rawValue: UInt64(key.flag.rawValue) | key.deviceFlagMask))
        }
    }

    private var leftCommandHeld: CGEventFlags {
        CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | Self.deviceLeftCommand)
    }

    private func keyEvent(_ keyCode: Int, down: Bool, flags: CGEventFlags = [], autorepeat: Bool = false) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: down)!
        event.flags = flags
        if autorepeat {
            event.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        }
        return event
    }

    private func flagsChangedEvent(keyCode: UInt16, flags: CGEventFlags) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)!
        event.type = .flagsChanged
        event.flags = flags
        return event
    }

    /// Sends a key and reports whether the manager let it through (false = swallowed).
    @discardableResult
    private func send(_ manager: HotkeyManager, key keyCode: Int, down: Bool, flags: CGEventFlags = [], autorepeat: Bool = false) -> Bool {
        let event = keyEvent(keyCode, down: down, flags: flags, autorepeat: autorepeat)
        return manager.handle(type: down ? .keyDown : .keyUp, event: event) != nil
    }

    /// Sends a `flagsChanged` for a modifier key; `flags` is the state after the change.
    @discardableResult
    private func send(_ manager: HotkeyManager, modifier keyCode: UInt16, flags: CGEventFlags) -> Bool {
        manager.handle(type: .flagsChanged, event: flagsChangedEvent(keyCode: keyCode, flags: flags)) != nil
    }

    /// Listeners are called on the next main-queue turn; let those turns run.
    private func deliver() {
        let delivered = expectation(description: "main queue drained")
        DispatchQueue.main.async { delivered.fulfill() }
        wait(for: [delivered], timeout: 2)
    }

    // MARK: - Modifier-only triggers

    func testRightOptionPressAndReleaseAreReportedAndPassedThrough() {
        let (manager, recorder) = makeManager(Hotkey(kind: .modifier(.rightOption)))
        XCTAssertTrue(send(manager, modifier: ModifierKey.rightOption.keyCode, flags: held(.rightOption)))
        deliver()
        XCTAssertEqual(recorder.events, [.pressed])

        XCTAssertTrue(send(manager, modifier: ModifierKey.rightOption.keyCode, flags: []))
        deliver()
        XCTAssertEqual(recorder.events, [.pressed, .released])
    }

    func testLeftOptionDoesNotTriggerRightOption() {
        let (manager, recorder) = makeManager(Hotkey(kind: .modifier(.rightOption)))
        send(manager, modifier: ModifierKey.leftOption.keyCode, flags: held(.leftOption))
        send(manager, modifier: ModifierKey.leftOption.keyCode, flags: [])
        deliver()
        XCTAssertEqual(recorder.events, [])
    }

    func testRightOptionDoesNotTriggerLeftOption() {
        let (manager, recorder) = makeManager(Hotkey(kind: .modifier(.leftOption)))
        send(manager, modifier: ModifierKey.rightOption.keyCode, flags: held(.rightOption))
        send(manager, modifier: ModifierKey.rightOption.keyCode, flags: [])
        deliver()
        XCTAssertEqual(recorder.events, [])

        send(manager, modifier: ModifierKey.leftOption.keyCode, flags: held(.leftOption))
        send(manager, modifier: ModifierKey.leftOption.keyCode, flags: [])
        deliver()
        XCTAssertEqual(recorder.events, [.pressed, .released])
    }

    func testReleaseIsDetectedByTheDeviceBitWhileTheOtherOptionKeyIsHeld() {
        // Both option keys share the ⌥ flag, so only the device bit shows Right ⌥ going up.
        let (manager, recorder) = makeManager(Hotkey(kind: .modifier(.rightOption)))
        send(manager, modifier: ModifierKey.leftOption.keyCode, flags: held(.leftOption))
        send(manager, modifier: ModifierKey.rightOption.keyCode, flags: held(.leftOption, .rightOption))
        send(manager, modifier: ModifierKey.rightOption.keyCode, flags: held(.leftOption))
        deliver()
        XCTAssertEqual(recorder.events, [.pressed, .released])
    }

    func testChordWithAnotherModifierIsNotAPress() {
        let (manager, recorder) = makeManager(Hotkey(kind: .modifier(.rightOption)))
        // ⌘ first, then Right ⌥: a ⌥⌘ shortcut, not dictation.
        send(manager, modifier: 55, flags: leftCommandHeld)
        send(manager, modifier: ModifierKey.rightOption.keyCode, flags: leftCommandHeld.union(held(.rightOption)))
        send(manager, modifier: ModifierKey.rightOption.keyCode, flags: leftCommandHeld)
        send(manager, modifier: 55, flags: [])
        deliver()
        XCTAssertEqual(recorder.events, [])
    }

    func testRepeatedFlagsChangedWhileHeldPressesOnlyOnce() {
        let (manager, recorder) = makeManager(Hotkey(kind: .modifier(.rightOption)))
        send(manager, modifier: ModifierKey.rightOption.keyCode, flags: held(.rightOption))
        send(manager, modifier: ModifierKey.rightOption.keyCode, flags: held(.rightOption))
        send(manager, modifier: ModifierKey.rightOption.keyCode, flags: [])
        send(manager, modifier: ModifierKey.rightOption.keyCode, flags: [])
        deliver()
        XCTAssertEqual(recorder.events, [.pressed, .released])
    }

    func testStrayReleaseReportsNothing() {
        let (manager, recorder) = makeManager(Hotkey(kind: .modifier(.rightOption)))
        send(manager, modifier: ModifierKey.rightOption.keyCode, flags: [])
        deliver()
        XCTAssertEqual(recorder.events, [])
    }

    func testTypingWithTheTriggerHeldInterruptsOnceAndIsNeverSwallowed() {
        // ⌥3 types "#" on a UK layout: the key must reach the app, and dictation must back off.
        let (manager, recorder) = makeManager(Hotkey(kind: .modifier(.rightOption)))
        send(manager, modifier: ModifierKey.rightOption.keyCode, flags: held(.rightOption))
        XCTAssertTrue(send(manager, key: kVK_ANSI_3, down: true, flags: held(.rightOption)))
        XCTAssertTrue(send(manager, key: kVK_ANSI_3, down: false, flags: held(.rightOption)))
        XCTAssertTrue(send(manager, key: kVK_ANSI_L, down: true, flags: held(.rightOption)))
        send(manager, modifier: ModifierKey.rightOption.keyCode, flags: [])
        deliver()
        XCTAssertEqual(recorder.events, [.pressed, .interrupted, .released])
    }

    func testTypingWithoutTheTriggerHeldReportsNothing() {
        let (manager, recorder) = makeManager(Hotkey(kind: .modifier(.rightOption)))
        XCTAssertTrue(send(manager, key: kVK_ANSI_A, down: true))
        XCTAssertTrue(send(manager, key: kVK_ANSI_A, down: false))
        deliver()
        XCTAssertEqual(recorder.events, [])
    }

    func testEachPressCanBeInterruptedAgain() {
        let (manager, recorder) = makeManager(Hotkey(kind: .modifier(.rightOption)))
        for _ in 0..<2 {
            send(manager, modifier: ModifierKey.rightOption.keyCode, flags: held(.rightOption))
            send(manager, key: kVK_ANSI_3, down: true, flags: held(.rightOption))
            send(manager, modifier: ModifierKey.rightOption.keyCode, flags: [])
        }
        deliver()
        XCTAssertEqual(recorder.events, [.pressed, .interrupted, .released, .pressed, .interrupted, .released])
    }

    func testFnTriggerUsesTheFunctionFlag() {
        let (manager, recorder) = makeManager(Hotkey(kind: .modifier(.fn)))
        send(manager, modifier: ModifierKey.fn.keyCode, flags: .maskSecondaryFn)
        send(manager, modifier: ModifierKey.fn.keyCode, flags: [])
        deliver()
        XCTAssertEqual(recorder.events, [.pressed, .released])
    }

    func testEveryModifierKeyWorksAsATrigger() {
        for key in ModifierKey.allCases {
            let (manager, recorder) = makeManager(Hotkey(kind: .modifier(key)))
            send(manager, modifier: key.keyCode, flags: held(key))
            send(manager, modifier: key.keyCode, flags: [])
            deliver()
            XCTAssertEqual(recorder.events, [.pressed, .released], "\(key)")
        }
    }

    // MARK: - Combo triggers

    private let optionSpace = Hotkey(kind: .combo(keyCode: UInt16(kVK_Space), modifiers: NSEvent.ModifierFlags.option.rawValue))

    func testComboPressAndReleaseAreReportedAndSwallowed() {
        let (manager, recorder) = makeManager(optionSpace)
        XCTAssertFalse(send(manager, key: kVK_Space, down: true, flags: .maskAlternate))
        XCTAssertFalse(send(manager, key: kVK_Space, down: false, flags: .maskAlternate))
        deliver()
        XCTAssertEqual(recorder.events, [.pressed, .released])
    }

    func testComboAutoRepeatIsSwallowedButNotReported() {
        let (manager, recorder) = makeManager(optionSpace)
        send(manager, key: kVK_Space, down: true, flags: .maskAlternate)
        for _ in 0..<3 {
            XCTAssertFalse(send(manager, key: kVK_Space, down: true, flags: .maskAlternate, autorepeat: true))
        }
        send(manager, key: kVK_Space, down: false, flags: .maskAlternate)
        deliver()
        XCTAssertEqual(recorder.events, [.pressed, .released])
    }

    func testComboNeedsExactlyItsModifiers() {
        let (manager, recorder) = makeManager(optionSpace)
        let wrong: [CGEventFlags] = [[], .maskCommand, [.maskAlternate, .maskCommand], [.maskAlternate, .maskShift]]
        for flags in wrong {
            XCTAssertTrue(send(manager, key: kVK_Space, down: true, flags: flags), "\(flags)")
            XCTAssertTrue(send(manager, key: kVK_Space, down: false, flags: flags), "\(flags)")
        }
        deliver()
        XCTAssertEqual(recorder.events, [])
    }

    func testComboIgnoresCapsLock() {
        let (manager, recorder) = makeManager(optionSpace)
        XCTAssertFalse(send(manager, key: kVK_Space, down: true, flags: [.maskAlternate, .maskAlphaShift]))
        XCTAssertFalse(send(manager, key: kVK_Space, down: false, flags: [.maskAlphaShift]))
        deliver()
        XCTAssertEqual(recorder.events, [.pressed, .released])
    }

    func testComboReleasedAfterItsModifierStillEnds() {
        let (manager, recorder) = makeManager(optionSpace)
        send(manager, key: kVK_Space, down: true, flags: .maskAlternate)
        XCTAssertFalse(send(manager, key: kVK_Space, down: false, flags: []))
        deliver()
        XCTAssertEqual(recorder.events, [.pressed, .released])
    }

    func testOtherKeysAndUnmatchedKeyUpsPassThrough() {
        let (manager, recorder) = makeManager(optionSpace)
        XCTAssertTrue(send(manager, key: kVK_Space, down: false, flags: .maskAlternate), "key-up without our key-down")
        XCTAssertTrue(send(manager, key: kVK_ANSI_A, down: true, flags: .maskAlternate))
        XCTAssertTrue(send(manager, modifier: ModifierKey.rightOption.keyCode, flags: held(.rightOption)))
        deliver()
        XCTAssertEqual(recorder.events, [])
    }

    func testChangingTheHotkeyForgetsAPressInProgress() {
        let (manager, recorder) = makeManager(optionSpace)
        send(manager, key: kVK_Space, down: true, flags: .maskAlternate)
        // The shortcut changes while the old one is still held; the new one must work at once.
        manager.hotkey = Hotkey(kind: .combo(keyCode: UInt16(kVK_Space), modifiers: NSEvent.ModifierFlags.control.rawValue))
        XCTAssertTrue(send(manager, key: kVK_Space, down: false, flags: .maskAlternate), "the old key-up is not ours")
        XCTAssertFalse(send(manager, key: kVK_Space, down: true, flags: .maskControl))
        deliver()
        XCTAssertEqual(recorder.events, [.pressed, .pressed])
    }

    // MARK: - Escape

    func testEscapeIsSwallowedAndReportedWhileDictating() {
        let (manager, recorder) = makeManager()
        manager.swallowEscape = true
        XCTAssertFalse(send(manager, key: kVK_Escape, down: true))
        XCTAssertTrue(send(manager, key: kVK_Escape, down: false), "only the key-down is swallowed")
        deliver()
        XCTAssertEqual(recorder.escapes, 1)
        XCTAssertEqual(recorder.events, [])
    }

    func testEscapeReachesTheAppWhenNotDictating() {
        let (manager, recorder) = makeManager()
        manager.swallowEscape = false
        XCTAssertTrue(send(manager, key: kVK_Escape, down: true))
        XCTAssertTrue(send(manager, key: kVK_Escape, down: false))
        deliver()
        XCTAssertEqual(recorder.escapes, 0)
    }

    // MARK: - Shortcut capture

    func testCapturingAModifierOnlyTrigger() {
        let (manager, recorder) = makeManager(optionSpace)
        beginCapture(on: manager, recorder: recorder)
        XCTAssertTrue(manager.isCapturing)
        XCTAssertTrue(send(manager, modifier: ModifierKey.rightCommand.keyCode, flags: held(.rightCommand)))
        XCTAssertTrue(send(manager, modifier: ModifierKey.rightCommand.keyCode, flags: []))
        deliver()
        XCTAssertEqual(recorder.captures, [Hotkey(kind: .modifier(.rightCommand))])
        XCTAssertFalse(manager.isCapturing)
        XCTAssertNil(manager.lastCaptureRejectionReason)
    }

    func testCapturingACombo() {
        let (manager, recorder) = makeManager()
        beginCapture(on: manager, recorder: recorder)
        XCTAssertFalse(send(manager, key: kVK_ANSI_D, down: false, flags: []), "stray key-ups are swallowed while capturing")
        XCTAssertFalse(send(manager, key: kVK_ANSI_D, down: true, flags: [.maskControl, .maskAlternate, .maskAlphaShift]))
        deliver()
        let expected = Hotkey(kind: .combo(
            keyCode: UInt16(kVK_ANSI_D),
            modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue
        ))
        XCTAssertEqual(recorder.captures, [expected])
        XCTAssertFalse(manager.isCapturing)
    }

    func testEscapeCancelsCapture() {
        let (manager, recorder) = makeManager()
        beginCapture(on: manager, recorder: recorder)
        XCTAssertFalse(send(manager, key: kVK_Escape, down: true))
        deliver()
        XCTAssertEqual(recorder.captures, [nil])
        XCTAssertFalse(manager.isCapturing)
        XCTAssertNil(manager.lastCaptureRejectionReason)
    }

    func testCaptureRejectsAKeyWithoutACommandOptionControlOrFnModifier() {
        for flags: CGEventFlags in [[], .maskShift] {
            let (manager, recorder) = makeManager()
            beginCapture(on: manager, recorder: recorder)
            XCTAssertFalse(send(manager, key: kVK_Space, down: true, flags: flags))
            deliver()
            XCTAssertEqual(recorder.captures, [nil], "\(flags)")
            XCTAssertEqual(manager.lastCaptureRejectionReason, "Hold ⌘, ⌥, ⌃ or Fn together with the key.")
        }
    }

    func testCaptureRejectsCommandOnlyShortcutsButAcceptsCommandWithOption() {
        let (manager, recorder) = makeManager()
        beginCapture(on: manager, recorder: recorder)
        send(manager, key: kVK_ANSI_Q, down: true, flags: .maskCommand)
        deliver()
        XCTAssertEqual(recorder.captures, [nil])
        XCTAssertEqual(manager.lastCaptureRejectionReason, "⌘ shortcuts are reserved by apps. Add ⌥, ⌃ or Fn.")

        beginCapture(on: manager, recorder: recorder)
        XCTAssertNil(manager.lastCaptureRejectionReason, "a new capture clears the old reason")
        send(manager, key: kVK_ANSI_Q, down: true, flags: [.maskCommand, .maskAlternate])
        deliver()
        let expected = Hotkey(kind: .combo(
            keyCode: UInt16(kVK_ANSI_Q),
            modifiers: NSEvent.ModifierFlags([.command, .option]).rawValue
        ))
        XCTAssertEqual(recorder.captures, [nil, expected])
    }

    func testCaptureIgnoresModifierChordsAndUnknownModifierKeys() {
        let (manager, recorder) = makeManager()
        beginCapture(on: manager, recorder: recorder)
        // Right ⌘ then Right ⌥ together, released in turn: a chord, not a single trigger key.
        send(manager, modifier: ModifierKey.rightCommand.keyCode, flags: held(.rightCommand))
        send(manager, modifier: ModifierKey.rightOption.keyCode, flags: held(.rightCommand, .rightOption))
        send(manager, modifier: ModifierKey.rightOption.keyCode, flags: held(.rightCommand))
        send(manager, modifier: ModifierKey.rightCommand.keyCode, flags: [])
        // Left ⌘ is not offered as a trigger.
        XCTAssertTrue(send(manager, modifier: 55, flags: leftCommandHeld))
        XCTAssertTrue(send(manager, modifier: 55, flags: []))
        deliver()
        XCTAssertEqual(recorder.captures, [])
        XCTAssertTrue(manager.isCapturing)

        manager.cancelCapture()
        deliver()
        XCTAssertEqual(recorder.captures, [nil])
    }

    func testCaptureSuspendsTheHotkey() {
        let (manager, recorder) = makeManager(Hotkey(kind: .modifier(.rightOption)))
        beginCapture(on: manager, recorder: recorder)
        send(manager, modifier: ModifierKey.rightOption.keyCode, flags: held(.rightOption))
        send(manager, modifier: ModifierKey.rightOption.keyCode, flags: [])
        deliver()
        XCTAssertEqual(recorder.events, [], "the key being recorded must not start dictation")
        XCTAssertEqual(recorder.captures, [Hotkey(kind: .modifier(.rightOption))])
    }

    func testCancelCaptureCompletesOnceWithNil() {
        let (manager, recorder) = makeManager()
        manager.cancelCapture() // Not capturing: nothing to cancel.
        beginCapture(on: manager, recorder: recorder)
        manager.cancelCapture()
        manager.cancelCapture()
        deliver()
        XCTAssertEqual(recorder.captures, [nil])
        XCTAssertFalse(manager.isCapturing)
    }

    // MARK: - Other events

    func testNonKeyboardEventsPassThroughUntouched() {
        let (manager, recorder) = makeManager()
        let event = keyEvent(kVK_Space, down: true)
        XCTAssertNotNil(manager.handle(type: .leftMouseDown, event: event))
        // No tap is installed, so there is nothing to re-enable; the event must still pass.
        XCTAssertNotNil(manager.handle(type: .tapDisabledByTimeout, event: event))
        XCTAssertNotNil(manager.handle(type: .tapDisabledByUserInput, event: event))
        deliver()
        XCTAssertEqual(recorder.events, [])
    }

    // MARK: - Device flags

    func testDeviceFlagMasksMatchTheIOKitBits() {
        // NX_DEVICELALTKEYMASK, NX_DEVICERALTKEYMASK, NX_DEVICERCMDKEYMASK, NX_DEVICERCTLKEYMASK,
        // NX_DEVICERSHIFTKEYMASK. Fn has no device bit.
        let expected: [ModifierKey: UInt64] = [
            .leftOption: 0x20, .rightOption: 0x40, .rightCommand: 0x10,
            .rightControl: 0x2000, .rightShift: 0x04, .fn: 0,
        ]
        for key in ModifierKey.allCases {
            XCTAssertEqual(key.deviceFlagMask, expected[key], "\(key)")
        }
        let nonZero = ModifierKey.allCases.map(\.deviceFlagMask).filter { $0 != 0 }
        XCTAssertEqual(Set(nonZero).count, nonZero.count, "each physical key has its own bit")
    }

    func testIsDownReadsOnlyTheKeysOwnDeviceBit() {
        for key in ModifierKey.allCases where key.deviceFlagMask != 0 {
            XCTAssertTrue(key.isDown(flags: key.flag, rawFlags: held(key)), "\(key)")
            // The shared flag alone (for example the other key of the pair) is not enough.
            XCTAssertFalse(key.isDown(flags: key.flag, rawFlags: CGEventFlags(rawValue: UInt64(key.flag.rawValue))), "\(key)")
            for other in ModifierKey.allCases where other != key && other.deviceFlagMask != 0 {
                XCTAssertFalse(key.isDown(flags: other.flag, rawFlags: held(other)), "\(key) vs \(other)")
            }
        }
    }

    func testFnIsDownFollowsTheFunctionFlag() {
        XCTAssertTrue(ModifierKey.fn.isDown(flags: .function, rawFlags: .maskSecondaryFn))
        XCTAssertFalse(ModifierKey.fn.isDown(flags: [], rawFlags: []))
        XCTAssertFalse(ModifierKey.fn.isDown(flags: .option, rawFlags: held(.rightOption)))
    }
}

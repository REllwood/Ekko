import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Foundation

enum HotkeyEvent: Sendable, Equatable {
    case pressed
    case released
    /// Another key was pressed while a modifier-only trigger was held (⌥3 for "#", ⌥L for "@",
    /// Fn+arrow…). The user was typing, not asking to dictate.
    case interrupted
}

enum HotkeyError: Error, LocalizedError, Equatable {
    case accessibilityNotGranted
    case eventTapFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityNotGranted: return "Accessibility access is required for the dictation shortcut."
        case .eventTapFailed: return "The keyboard shortcut listener could not be installed."
        }
    }
}

/// Global hotkey listener built on a CGEventTap.
/// Emits raw pressed/released events; `DictationController` applies the activation mode.
@Observable
@MainActor
final class HotkeyManager {
    /// The trigger to listen for. Changing it takes effect immediately while running.
    var hotkey: Hotkey = .default
    private(set) var isRunning = false
    private(set) var isCapturing = false
    /// Set when the tap could not be created; cleared on a successful `start()`.
    private(set) var lastError: HotkeyError?
    /// Why the last shortcut capture was refused, for the Settings UI. Cleared by `beginCapture`.
    private(set) var lastCaptureRejectionReason: String?

    /// Set by `DictationController` while a dictation is running: Escape is then swallowed and
    /// reported through `onEscape` instead of reaching the focused app.
    var swallowEscape = false

    @ObservationIgnored var onEvent: ((HotkeyEvent) -> Void)?
    /// Called when Escape is pressed while `swallowEscape` is true.
    @ObservationIgnored var onEscape: (() -> Void)?

    @ObservationIgnored private var eventTap: CFMachPort?
    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    /// True between the `.pressed` and `.released` we emitted, so repeats never double-fire.
    @ObservationIgnored private var isHotkeyDown = false
    /// Set once `.interrupted` has been sent for the press that is still down.
    @ObservationIgnored private var didInterruptCurrentPress = false
    @ObservationIgnored private var matchedHotkey: Hotkey?
    @ObservationIgnored private var captureCompletion: ((Hotkey?) -> Void)?
    @ObservationIgnored private var captureCandidate: ModifierKey?

    /// The modifier flags we compare; everything else (caps lock, numeric pad) is ignored.
    static let relevantFlags: NSEvent.ModifierFlags = [.command, .option, .control, .shift, .function]
    /// A combo must include at least one of these (⇧ alone is not a shortcut).
    static let qualifyingFlags: NSEvent.ModifierFlags = [.command, .option, .control, .function]

    init() {}

    // MARK: - Lifecycle

    func start() throws {
        guard !isRunning else { return }
        // `tapCreate` silently drops the keyDown/keyUp bits when we are not trusted, so a non-nil
        // tap proves nothing — gate on the trust flag instead.
        guard AXIsProcessTrusted() else {
            lastError = .accessibilityNotGranted
            throw HotkeyError.accessibilityNotGranted
        }

        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: ekkoHotkeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            lastError = .eventTapFailed
            Log.input.error("CGEvent.tapCreate returned nil while trusted")
            // Diagnostic: some systems additionally require Input Monitoring.
            if !CGPreflightListenEventAccess() {
                _ = CGRequestListenEventAccess()
            }
            throw HotkeyError.eventTapFailed
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            lastError = .eventTapFailed
            throw HotkeyError.eventTapFailed
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        isHotkeyDown = false
        matchedHotkey = hotkey
        lastError = nil
        isRunning = true
        Log.input.info("Hotkey tap installed for \(self.hotkey.displayString, privacy: .public)")
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        runLoopSource = nil
        eventTap = nil
        isHotkeyDown = false
        isRunning = false
    }

    /// Tears the tap down and installs it again (after a permission change, for example).
    func restart() {
        stop()
        do {
            try start()
        } catch {
            Log.input.error("Hotkey restart failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Shortcut capture

    /// Enters capture mode: the next key (modifier-only or key+modifiers) pressed by the user is
    /// reported and normal hotkey handling is suspended. Esc cancels (completion receives nil).
    func beginCapture(_ completion: @escaping (Hotkey?) -> Void) {
        lastCaptureRejectionReason = nil
        captureCandidate = nil
        captureCompletion = completion
        isCapturing = true
        // A key may still be physically down from the click that started capture.
        isHotkeyDown = false
    }

    func cancelCapture() {
        guard isCapturing else { return }
        finishCapture(nil, reason: nil)
    }

    private func finishCapture(_ result: Hotkey?, reason: String?) {
        let completion = captureCompletion
        captureCompletion = nil
        captureCandidate = nil
        isCapturing = false
        lastCaptureRejectionReason = reason
        guard let completion else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated { completion(result) }
        }
    }

    // MARK: - Event handling (runs on the main thread, from the tap callback)

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passthrough = Unmanaged.passUnretained(event)

        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
                Log.input.debug("Event tap re-enabled after \(String(describing: type), privacy: .public)")
            }
            return passthrough
        case .keyDown, .keyUp, .flagsChanged:
            break
        default:
            return passthrough
        }

        let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
            .intersection(.deviceIndependentFlagsMask)

        if isCapturing {
            return handleCapture(type: type, keyCode: keyCode, flags: flags, rawFlags: event.flags, passthrough: passthrough)
        }

        if swallowEscape, type == .keyDown, keyCode == UInt16(kVK_Escape) {
            emitEscape()
            return nil
        }

        if matchedHotkey != hotkey {
            matchedHotkey = hotkey
            isHotkeyDown = false
        }

        switch hotkey.kind {
        case .modifier(let key):
            return handleModifier(
                key: key, type: type, keyCode: keyCode, flags: flags,
                rawFlags: event.flags, passthrough: passthrough
            )
        case .combo(let comboKeyCode, let modifiers):
            return handleCombo(
                comboKeyCode: comboKeyCode, modifiers: modifiers, type: type,
                keyCode: keyCode, flags: flags, event: event, passthrough: passthrough
            )
        }
    }

    /// Modifier-only triggers. Decided by key code (never by the flag alone) and never swallowed.
    private func handleModifier(
        key: ModifierKey,
        type: CGEventType,
        keyCode: UInt16,
        flags: NSEvent.ModifierFlags,
        rawFlags: CGEventFlags,
        passthrough: Unmanaged<CGEvent>
    ) -> Unmanaged<CGEvent>? {
        if type == .keyDown {
            // The modifier is being used to type something; never swallow the key itself.
            if isHotkeyDown, !didInterruptCurrentPress {
                didInterruptCurrentPress = true
                emit(.interrupted)
            }
            return passthrough
        }
        guard type == .flagsChanged, keyCode == key.keyCode else { return passthrough }

        if key.isDown(flags: flags, rawFlags: rawFlags) {
            // ⌥⌘-style chords must not trigger dictation.
            let others = flags.intersection(Self.relevantFlags).subtracting(key.flag)
            guard others.isEmpty else { return passthrough }
            if !isHotkeyDown {
                isHotkeyDown = true
                didInterruptCurrentPress = false
                emit(.pressed)
            }
        } else if isHotkeyDown {
            isHotkeyDown = false
            emit(.released)
        }
        return passthrough
    }

    /// Key + modifier triggers. The matching events are swallowed so the app never sees them.
    private func handleCombo(
        comboKeyCode: UInt16,
        modifiers: UInt,
        type: CGEventType,
        keyCode: UInt16,
        flags: NSEvent.ModifierFlags,
        event: CGEvent,
        passthrough: Unmanaged<CGEvent>
    ) -> Unmanaged<CGEvent>? {
        guard type == .keyDown || type == .keyUp, keyCode == comboKeyCode else { return passthrough }

        if type == .keyUp {
            // The user may release the modifier before the key; the key-up still ends the press.
            guard isHotkeyDown else { return passthrough }
            isHotkeyDown = false
            emit(.released)
            return nil
        }

        let wanted = NSEvent.ModifierFlags(rawValue: modifiers).intersection(Self.relevantFlags)
        guard flags.intersection(Self.relevantFlags) == wanted else { return passthrough }
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if isRepeat { return nil }
        if !isHotkeyDown {
            isHotkeyDown = true
            emit(.pressed)
        }
        return nil
    }

    private func handleCapture(
        type: CGEventType,
        keyCode: UInt16,
        flags: NSEvent.ModifierFlags,
        rawFlags: CGEventFlags,
        passthrough: Unmanaged<CGEvent>
    ) -> Unmanaged<CGEvent>? {
        switch type {
        case .keyDown:
            if keyCode == UInt16(kVK_Escape) {
                finishCapture(nil, reason: nil)
                return nil
            }
            let relevant = flags.intersection(Self.relevantFlags)
            guard !relevant.intersection(Self.qualifyingFlags).isEmpty else {
                finishCapture(nil, reason: "Hold ⌘, ⌥, ⌃ or Fn together with the key.")
                return nil
            }
            // ⌘ + a single key is app-shortcut territory (⌘Q, ⌘W, ⌘Tab); refuse it.
            if relevant.contains(.command), relevant.intersection([.option, .control, .function]).isEmpty {
                finishCapture(nil, reason: "⌘ shortcuts are reserved by apps. Add ⌥, ⌃ or Fn.")
                return nil
            }
            finishCapture(Hotkey(kind: .combo(keyCode: keyCode, modifiers: relevant.rawValue)), reason: nil)
            return nil

        case .keyUp:
            // Swallow the tail of the captured combo.
            return nil

        case .flagsChanged:
            guard let key = ModifierKey.from(keyCode: keyCode) else { return passthrough }
            if key.isDown(flags: flags, rawFlags: rawFlags) {
                let others = flags.intersection(Self.relevantFlags).subtracting(key.flag)
                captureCandidate = others.isEmpty ? key : nil
            } else if captureCandidate == key {
                finishCapture(Hotkey(kind: .modifier(key)), reason: nil)
            }
            return passthrough

        default:
            return passthrough
        }
    }

    // MARK: - Callback dispatch

    /// The tap callback must return quickly, so listeners are invoked on the next main-queue turn.
    private func emit(_ event: HotkeyEvent) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.onEvent?(event)
            }
        }
    }

    private func emitEscape() {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.onEscape?()
            }
        }
    }
}

extension ModifierKey {
    /// Device-dependent CGEventFlags bit for this physical key, so left/right keys can be told
    /// apart even while the other one is held. 0 when there is none (Fn).
    var deviceFlagMask: UInt64 {
        switch self {
        case .fn: return 0
        case .leftOption: return 0x0000_0020
        case .rightOption: return 0x0000_0040
        case .rightCommand: return 0x0000_0010
        case .rightControl: return 0x0000_2000
        case .rightShift: return 0x0000_0004
        }
    }

    /// True when this key is held according to the flags of a `flagsChanged` event.
    func isDown(flags: NSEvent.ModifierFlags, rawFlags: CGEventFlags) -> Bool {
        let mask = deviceFlagMask
        if mask != 0 {
            return (rawFlags.rawValue & mask) != 0
        }
        return flags.contains(flag)
    }
}

/// C entry point for the tap. The run loop source lives on the main run loop, so this always runs
/// on the main thread and may touch the manager directly.
private func ekkoHotkeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
    return MainActor.assumeIsolated {
        manager.handle(type: type, event: event)
    }
}

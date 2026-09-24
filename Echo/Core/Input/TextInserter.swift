import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// How text reaches the target app.
enum InsertionMethod: String, Codable, CaseIterable, Sendable {
    /// Paste (restoring the clipboard afterwards), then synthesized typing if pasting fails.
    case auto
    case paste
    case accessibility
    case type

    var title: String {
        switch self {
        case .auto: return "Automatic"
        case .paste: return "Paste (⌘V)"
        case .accessibility: return "Accessibility"
        case .type: return "Type keystrokes"
        }
    }

    var detail: String {
        switch self {
        case .auto: return "Picks the most reliable method for the app you're in."
        case .paste: return "Puts the text on the clipboard and pastes it. Works almost everywhere."
        case .accessibility: return "Inserts directly at the cursor without touching the clipboard."
        case .type: return "Simulates typing. Slow, but works in apps that block pasting."
        }
    }
}

/// What was focused when dictation started. Captured before the microphone opens.
struct FocusContext: Sendable, Equatable {
    var appBundleID: String?
    var appName: String?
    var appPID: pid_t?
    /// AX role of the focused element, e.g. "AXTextArea".
    var elementRole: String?
    var isSecureField: Bool = false
    /// Whether the element exposed `AXSelectedText` as settable.
    var supportsAXInsertion: Bool = false
    /// Up to ~64 characters immediately before the caret, when readable.
    var textBeforeCursor: String?
    /// Currently selected text (will be replaced), when readable.
    var selectedText: String?
    /// True when the element appeared empty.
    var isFieldEmpty: Bool?
}

enum InsertionOutcome: Equatable, Sendable {
    case inserted(InsertionMethod)
    /// Nothing could be inserted; the text was left on the clipboard for the user.
    case leftOnClipboard
}

enum InsertionError: Error, LocalizedError, Equatable {
    case noFocusedElement
    case accessibilityNotGranted
    case targetIsSelf
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noFocusedElement: return "No text field is focused."
        case .accessibilityNotGranted: return "Accessibility access is required to insert text."
        case .targetIsSelf: return "Cannot insert into Echo itself."
        case .failed(let detail): return detail
        }
    }
}

/// Puts text into the frontmost app.
final class TextInserter {
    /// Private pasteboard type that marks the clipboard contents as ours, so a restore never
    /// clobbers something the user copied while we were pasting.
    static let markerType = NSPasteboard.PasteboardType("com.rhysellwood.echo.session")

    /// Virtual key codes (US layout independent).
    private enum Key {
        static let command: CGKeyCode = 0x37
        static let v: CGKeyCode = 0x09
        static let `return`: CGKeyCode = 0x24
    }

    /// Timings, in nanoseconds.
    private enum Delay {
        static let beforePaste: UInt64 = 100_000_000
        static let betweenKeyEvents: UInt64 = 10_000_000
        static let beforeRestore: UInt64 = 320_000_000
        static let betweenTypeChunks: UInt64 = 2_000_000
    }

    /// Maximum UTF-16 units per synthesized keyboard event.
    private static let typeChunkLimit = 20

    init() {}

    /// Reads the frontmost app and focused AX element. Cheap; call at the start of dictation.
    @MainActor
    func captureFocusContext() -> FocusContext {
        let context = FocusContextReader.capture()
        Log.input.debug("Focus: \(context.appBundleID ?? "unknown", privacy: .public) role=\(context.elementRole ?? "-", privacy: .public) axSettable=\(context.supportsAXInsertion, privacy: .public)")
        return context
    }

    /// Inserts `text` using `method` (resolving `.auto`). Never throws for a plain
    /// insertion miss — returns `.leftOnClipboard` instead — but throws for hard errors.
    @MainActor
    func insert(_ text: String, context: FocusContext, method: InsertionMethod, restoreClipboard: Bool) async -> InsertionOutcome {
        guard !text.isEmpty else { return .inserted(method) }
        guard AXIsProcessTrusted() else {
            // Without Accessibility we cannot type or paste for the user, but the words are not
            // lost: leave them on the clipboard, which is exactly what the HUD will tell them.
            Log.input.info("Accessibility not granted; leaving the transcript on the clipboard")
            writeTextOnly(text)
            return .leftOnClipboard
        }
        await returnFocusToTarget(of: context)

        switch method {
        case .accessibility:
            if insertViaAccessibility(text, context: context) {
                return .inserted(.accessibility)
            }
            Log.input.debug("AX insertion unavailable; falling back to paste")
            return await pasteThenType(text, restoreClipboard: restoreClipboard, allowTyping: true)

        case .paste:
            return await pasteThenType(text, restoreClipboard: restoreClipboard, allowTyping: false)

        case .type:
            if await typeText(text) { return .inserted(.type) }
            writeTextOnly(text)
            return .leftOnClipboard

        case .auto:
            return await pasteThenType(text, restoreClipboard: restoreClipboard, allowTyping: true)
        }
    }

    // MARK: - Strategies

    /// The `.auto` workhorse: clipboard paste, then synthesized typing if the paste keystrokes
    /// could not be posted. The text stays on the clipboard when everything fails.
    @MainActor
    private func pasteThenType(_ text: String, restoreClipboard: Bool, allowTyping: Bool) async -> InsertionOutcome {
        let snapshot = PasteboardSnapshot.capture()
        let marker = UUID().uuidString
        writeToPasteboard(text, marker: marker)
        try? await Task.sleep(nanoseconds: Delay.beforePaste)

        if await postPasteShortcut() {
            scheduleRestore(snapshot, marker: marker, enabled: restoreClipboard)
            return .inserted(.paste)
        }

        Log.input.error("Could not post ⌘V; falling back")
        if allowTyping, await typeText(text) {
            scheduleRestore(snapshot, marker: marker, enabled: restoreClipboard)
            return .inserted(.type)
        }
        // Leave our text on the clipboard so the user can paste it themselves.
        return .leftOnClipboard
    }

    /// Sets `AXSelectedText` on the element that has focus *now* and verifies the write landed.
    @MainActor
    private func insertViaAccessibility(_ text: String, context: FocusContext) -> Bool {
        guard !context.isSecureField else { return false }
        guard let element = FocusContextReader.focusedElement() else { return false }
        let subrole = FocusContextReader.string(element, kAXSubroleAttribute)
        guard subrole != (kAXSecureTextFieldSubrole as String) else { return false }
        guard FocusContextReader.isSettable(element, kAXSelectedTextAttribute) else { return false }

        let caret = FocusContextReader.selectedRange(element)?.location
        let valueBefore = FocusContextReader.string(element, kAXValueAttribute)
        guard FocusContextReader.setSelectedText(element, text) else { return false }

        // Verify: the value should now contain our text at (or around) the old caret.
        guard let valueAfter = FocusContextReader.string(element, kAXValueAttribute) else {
            // The element does not expose its value; trust the successful write rather than
            // risk inserting the text twice.
            return true
        }
        if let caret, let inserted = FocusContextReader.substring(of: valueAfter, location: caret, length: text.utf16.count),
           inserted == text {
            return true
        }
        if valueAfter != valueBefore, valueAfter.contains(text) { return true }
        Log.input.debug("AX insertion could not be verified")
        return false
    }

    // MARK: - Pasteboard

    @MainActor
    private func writeToPasteboard(_ text: String, marker: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, Self.markerType], owner: nil)
        pasteboard.setString(text, forType: .string)
        pasteboard.setString(marker, forType: Self.markerType)
    }

    @MainActor
    private func writeTextOnly(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(text, forType: .string)
    }

    /// Restores the user's clipboard once the target app has had time to read ours — but only if
    /// the clipboard is still the one we wrote.
    @MainActor
    private func scheduleRestore(_ snapshot: PasteboardSnapshot, marker: String, enabled: Bool) {
        guard enabled else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: Delay.beforeRestore)
            let pasteboard = NSPasteboard.general
            guard pasteboard.string(forType: Self.markerType) == marker else {
                Log.input.debug("Clipboard changed during paste; leaving it alone")
                return
            }
            snapshot.restore(to: pasteboard)
        }
    }

    // MARK: - Synthesized keyboard events

    @MainActor
    private func postPasteShortcut() async -> Bool {
        guard let source = CGEventSource(stateID: .privateState) else { return false }
        guard let commandDown = CGEvent(keyboardEventSource: source, virtualKey: Key.command, keyDown: true),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: Key.v, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: Key.v, keyDown: false),
              let commandUp = CGEvent(keyboardEventSource: source, virtualKey: Key.command, keyDown: false) else {
            return false
        }
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand

        commandDown.post(tap: .cghidEventTap)
        try? await Task.sleep(nanoseconds: Delay.betweenKeyEvents)
        vDown.post(tap: .cghidEventTap)
        try? await Task.sleep(nanoseconds: Delay.betweenKeyEvents)
        vUp.post(tap: .cghidEventTap)
        try? await Task.sleep(nanoseconds: Delay.betweenKeyEvents)
        commandUp.post(tap: .cghidEventTap)
        return true
    }

    /// Types the text as unicode keystrokes, in small chunks so apps keep up.
    @MainActor
    private func typeText(_ text: String) async -> Bool {
        guard let source = CGEventSource(stateID: .privateState) else { return false }
        let lines = text.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            if index > 0 {
                guard postReturn(source: source) else { return false }
                try? await Task.sleep(nanoseconds: Delay.betweenTypeChunks)
            }
            for chunk in Self.chunks(of: line, maxUTF16: Self.typeChunkLimit) {
                guard postUnicode(chunk, source: source) else { return false }
                try? await Task.sleep(nanoseconds: Delay.betweenTypeChunks)
            }
        }
        return true
    }

    private func postUnicode(_ chunk: String, source: CGEventSource) -> Bool {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { return false }
        var units = Array(chunk.utf16)
        guard !units.isEmpty else { return true }
        down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
        up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    private func postReturn(source: CGEventSource) -> Bool {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: Key.return, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: Key.return, keyDown: false) else { return false }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    /// Splits on grapheme boundaries so surrogate pairs are never cut in half.
    static func chunks(of text: String, maxUTF16: Int) -> [String] {
        guard !text.isEmpty else { return [] }
        var chunks: [String] = []
        var current = ""
        var count = 0
        for character in text {
            let width = character.utf16.count
            if count + width > maxUTF16, !current.isEmpty {
                chunks.append(current)
                current = ""
                count = 0
            }
            current.append(character)
            count += width
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    /// Echo can end up frontmost mid-dictation (the menu-bar popover activates it). The text must
    /// go to the app the user was dictating into, so hand focus back to it first. Dictating into
    /// Echo's own window (the onboarding practice box) is left alone.
    @MainActor
    private func returnFocusToTarget(of context: FocusContext) async {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard isFrontmostSelf(), let pid = context.appPID, pid != ownPID,
              let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return }
        Log.input.info("Echo is frontmost; returning focus to \(app.localizedName ?? "the target app", privacy: .public)")
        app.activate()
        for _ in 0..<20 where isFrontmostSelf() {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        // Give the app a moment to restore its key window and text focus.
        try? await Task.sleep(nanoseconds: 120_000_000)
    }

    @MainActor
    private func isFrontmostSelf() -> Bool {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return false }
        if let bundleID = frontmost.bundleIdentifier, bundleID == Bundle.main.bundleIdentifier { return true }
        return frontmost.processIdentifier == ProcessInfo.processInfo.processIdentifier
    }
}

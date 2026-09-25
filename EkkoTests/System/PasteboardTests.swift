import AppKit
import XCTest
@testable import Ekko

/// Uses private, uniquely named pasteboards; the user's clipboard is never read or written.
@MainActor
final class PasteboardSnapshotTests: XCTestCase {
    private static let customType = NSPasteboard.PasteboardType("com.rhysellwood.ekko.tests.custom")

    private func makePasteboard() -> NSPasteboard {
        let temporary = TemporaryPasteboard()
        addTeardownBlock { temporary.remove() }
        return temporary.pasteboard
    }

    private func item(_ contents: [NSPasteboard.PasteboardType: Data]) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        for (type, data) in contents {
            item.setData(data, forType: type)
        }
        return item
    }

    func testCapturesEveryItemAndType() {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.writeObjects([
            item([.string: Data("first".utf8), Self.customType: Data([1, 2, 3])]),
            item([.string: Data("second".utf8), .html: Data("<b>second</b>".utf8)]),
        ])

        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        XCTAssertEqual(snapshot.items.count, 2)
        XCTAssertFalse(snapshot.isEmpty)
        XCTAssertEqual(snapshot.items[0].contents[NSPasteboard.PasteboardType.string.rawValue], Data("first".utf8))
        XCTAssertEqual(snapshot.items[0].contents[Self.customType.rawValue], Data([1, 2, 3]))
        XCTAssertEqual(snapshot.items[1].contents[NSPasteboard.PasteboardType.string.rawValue], Data("second".utf8))
        XCTAssertEqual(snapshot.items[1].contents[NSPasteboard.PasteboardType.html.rawValue], Data("<b>second</b>".utf8))
    }

    func testRestorePutsBackExactlyWhatWasCaptured() {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        pasteboard.writeObjects([
            item([.string: Data("first".utf8), Self.customType: Data([9, 8, 7])]),
            item([.string: Data("second".utf8), .rtf: Data("{\\rtf1 second}".utf8)]),
        ])
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        // Something else takes over the clipboard, then the snapshot goes back.
        pasteboard.clearContents()
        pasteboard.setString("the transcript", forType: .string)
        snapshot.restore(to: pasteboard)

        XCTAssertEqual(PasteboardSnapshot.capture(from: pasteboard), snapshot)
        XCTAssertEqual(pasteboard.pasteboardItems?.count, 2)
        XCTAssertEqual(pasteboard.pasteboardItems?.first?.string(forType: .string), "first")
        XCTAssertEqual(pasteboard.pasteboardItems?.first?.data(forType: Self.customType), Data([9, 8, 7]))
        XCTAssertEqual(pasteboard.pasteboardItems?.last?.string(forType: .string), "second")
        XCTAssertFalse(pasteboard.types?.contains(TextInserter.markerType) ?? false)
    }

    func testEmptyPasteboardCapturesAsEmpty() {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        XCTAssertTrue(snapshot.items.isEmpty)
        XCTAssertTrue(snapshot.isEmpty)
    }

    func testRestoringAnEmptySnapshotLeavesTheClipboardEmpty() {
        let pasteboard = makePasteboard()
        pasteboard.clearContents()
        let empty = PasteboardSnapshot.capture(from: pasteboard)

        pasteboard.setString("the transcript", forType: .string)
        empty.restore(to: pasteboard)
        XCTAssertNil(pasteboard.string(forType: .string))
        XCTAssertTrue(PasteboardSnapshot.capture(from: pasteboard).isEmpty)
    }

    func testItemsWithoutDataCountAsEmpty() {
        XCTAssertTrue(PasteboardSnapshot().isEmpty)
        XCTAssertTrue(PasteboardSnapshot(items: [.init(contents: [:])]).isEmpty)
        XCTAssertFalse(PasteboardSnapshot(items: [.init(contents: [:]), .init(contents: ["public.utf8-plain-text": Data()])]).isEmpty)
    }
}

/// The clipboard side of `TextInserter`: the session marker, the guarded restore, and the
/// fallback without Accessibility. No keyboard events are posted.
@MainActor
final class TextInserterPasteboardTests: XCTestCase {
    private func makeInserter(trusted: Bool = false) -> TextInserter {
        let temporary = TemporaryPasteboard()
        addTeardownBlock { temporary.remove() }
        return TextInserter(pasteboard: temporary.pasteboard, isAccessibilityTrusted: { trusted })
    }

    func testTranscriptIsTaggedWithTheSessionMarker() {
        let inserter = makeInserter()
        inserter.writeToPasteboard("hello there", marker: "session-1")
        XCTAssertEqual(inserter.pasteboard.string(forType: .string), "hello there")
        XCTAssertEqual(inserter.pasteboard.string(forType: TextInserter.markerType), "session-1")
    }

    func testRestoreBringsBackTheUsersClipboard() {
        let inserter = makeInserter()
        let pasteboard = inserter.pasteboard
        pasteboard.clearContents()
        pasteboard.setString("what the user copied", forType: .string)
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        inserter.writeToPasteboard("the transcript", marker: "session-1")
        XCTAssertTrue(inserter.restoreIfUnchanged(snapshot, marker: "session-1"))
        XCTAssertEqual(pasteboard.string(forType: .string), "what the user copied")
        XCTAssertNil(pasteboard.string(forType: TextInserter.markerType), "the marker must not linger")
    }

    func testSomethingCopiedDuringThePasteIsLeftAlone() {
        let inserter = makeInserter()
        let pasteboard = inserter.pasteboard
        pasteboard.clearContents()
        pasteboard.setString("old clipboard", forType: .string)
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        inserter.writeToPasteboard("the transcript", marker: "session-1")
        pasteboard.clearContents()
        pasteboard.setString("copied a moment ago", forType: .string)

        XCTAssertFalse(inserter.restoreIfUnchanged(snapshot, marker: "session-1"))
        XCTAssertEqual(pasteboard.string(forType: .string), "copied a moment ago")
    }

    func testALaterSessionsTranscriptIsLeftAlone() {
        let inserter = makeInserter()
        let snapshot = PasteboardSnapshot(items: [.init(contents: ["public.utf8-plain-text": Data("old".utf8)])])
        inserter.writeToPasteboard("first dictation", marker: "session-1")
        inserter.writeToPasteboard("second dictation", marker: "session-2")

        XCTAssertFalse(inserter.restoreIfUnchanged(snapshot, marker: "session-1"))
        XCTAssertEqual(inserter.pasteboard.string(forType: .string), "second dictation")
    }

    func testWithoutAccessibilityTheTranscriptIsLeftOnTheClipboard() async {
        let inserter = makeInserter(trusted: false)
        let outcome = await inserter.insert(
            "words worth keeping",
            context: FocusContext(appBundleID: "com.apple.TextEdit", appPID: 1),
            method: .auto,
            restoreClipboard: true
        )
        XCTAssertEqual(outcome, .leftOnClipboard)
        XCTAssertEqual(inserter.pasteboard.string(forType: .string), "words worth keeping")
        XCTAssertNil(
            inserter.pasteboard.string(forType: TextInserter.markerType),
            "no marker, so no later restore can take the words away"
        )
    }

    func testEmptyTextNeedsNoInsertion() async {
        let inserter = makeInserter(trusted: false)
        inserter.pasteboard.clearContents()
        inserter.pasteboard.setString("untouched", forType: .string)
        let outcome = await inserter.insert("", context: FocusContext(), method: .type, restoreClipboard: true)
        XCTAssertEqual(outcome, .inserted(.type))
        XCTAssertEqual(inserter.pasteboard.string(forType: .string), "untouched")
    }
}

final class TextInserterChunkTests: XCTestCase {
    private func assertChunks(
        _ text: String,
        limit: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let chunks = TextInserter.chunks(of: text, maxUTF16: limit)
        XCTAssertEqual(chunks.joined(), text, "nothing lost or reordered", file: file, line: line)
        // Chunk boundaries fall between characters: every chunk holds whole characters.
        XCTAssertEqual(chunks.flatMap { Array($0) }, Array(text), file: file, line: line)
        for chunk in chunks {
            XCTAssertFalse(chunk.isEmpty, file: file, line: line)
            XCTAssertTrue(
                chunk.utf16.count <= limit || chunk.count == 1,
                "\"\(chunk)\" is \(chunk.utf16.count) units; only a single oversized character may exceed \(limit)",
                file: file, line: line
            )
            XCTAssertNotNil(String(utf16CodeUnits: Array(chunk.utf16), count: chunk.utf16.count), file: file, line: line)
        }
    }

    func testEmptyTextHasNoChunks() {
        XCTAssertEqual(TextInserter.chunks(of: "", maxUTF16: 20), [])
    }

    func testPlainTextIsSplitAtTheLimit() {
        let text = String(repeating: "abcde", count: 9) // 45 units
        XCTAssertEqual(TextInserter.chunks(of: text, maxUTF16: 20).map(\.utf16.count), [20, 20, 5])
        XCTAssertEqual(TextInserter.chunks(of: "short", maxUTF16: 20), ["short"])
    }

    func testSurrogatePairsAreNeverSplit() {
        let text = String(repeating: "😀", count: 15) // 30 units, 2 per emoji
        let chunks = TextInserter.chunks(of: text, maxUTF16: 21)
        XCTAssertEqual(chunks.map(\.utf16.count), [20, 10], "an odd limit must not cut a pair in half")
        assertChunks(text, limit: 21)
    }

    func testComposedCharactersStayWhole() {
        let family = "👨‍👩‍👧‍👦"          // 11 UTF-16 units, one character
        let flag = "🇬🇧"                // 4 units
        let accented = "e\u{301}"       // e + combining acute
        XCTAssertEqual(family.utf16.count, 11)
        XCTAssertEqual(TextInserter.chunks(of: "a\(family)b", maxUTF16: 5), ["a", family, "b"])
        XCTAssertEqual(TextInserter.chunks(of: "\(flag)\(flag)\(flag)", maxUTF16: 6), [flag, flag, flag])
        XCTAssertEqual(TextInserter.chunks(of: "caf\(accented)", maxUTF16: 4), ["caf", accented])
    }

    func testMixedTextAtEveryLimit() {
        let samples = [
            "Hello, world!",
            "Grüße aus Köln 🇩🇪 — schön.",
            "日本語のテキストと😀絵文字👍🏽",
            "👨‍👩‍👧‍👦👩🏽‍💻🏳️‍🌈 family, coder, flag",
            "Zalgo: Z\u{0351}\u{036B}\u{0343}a\u{0310}l\u{0351}g\u{0301}o",
            "e\u{301}e\u{301}e\u{301}e\u{301}",
        ]
        for text in samples {
            for limit in 1...25 {
                assertChunks(text, limit: limit)
            }
        }
    }
}

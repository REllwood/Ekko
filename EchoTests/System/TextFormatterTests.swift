import XCTest
@testable import Echo

final class TextFormatterTests: XCTestCase {
    private let formatter = TextFormatter()

    private func context(
        before: String? = nil,
        selected: String? = nil,
        empty: Bool? = nil
    ) -> FocusContext {
        var context = FocusContext()
        context.appBundleID = "com.apple.TextEdit"
        context.appName = "TextEdit"
        context.textBeforeCursor = before
        context.selectedText = selected
        context.isFieldEmpty = empty
        return context
    }

    // MARK: - Trimming

    func testTrimsAndCollapsesWhitespace() {
        let cases: [(String, String)] = [
            ("  hello world  ", "hello world"),
            ("hello    world", "hello world"),
            ("hello\tworld", "hello world"),
            ("hello \n world", "hello\nworld"),
        ]
        for (input, expected) in cases {
            let result = formatter.format(input, context: nil, options: TextFormatter.Options())
            XCTAssertEqual(result, expected, "input: \(input)")
        }
    }

    func testEmptyInputStaysEmpty() {
        XCTAssertEqual(formatter.format("   \n ", context: nil, options: TextFormatter.Options()), "")
    }

    // MARK: - Smart spacing

    func testSmartSpacing() {
        let options = TextFormatter.Options(smartCapitalization: false, smartSpacing: true)
        let cases: [(String?, String, String)] = [
            (nil, "world", "world"),                     // unknown context -> never guess
            ("", "world", "world"),                      // caret at the very start
            ("hello", "world", " world"),                // after a word
            ("hello ", "world", "world"),                // already spaced
            ("hello\n", "world", "world"),               // start of a line
            ("(", "world", "world"),                     // opening bracket
            ("[", "world", "world"),
            ("\"", "world", "world"),
            ("path/", "world", "world"),
        ]
        for (before, input, expected) in cases {
            let result = formatter.format(input, context: context(before: before), options: options)
            XCTAssertEqual(result, expected, "before: \(before ?? "nil")")
        }
    }

    func testSmartSpacingDisabled() {
        let options = TextFormatter.Options(smartCapitalization: false, smartSpacing: false)
        XCTAssertEqual(formatter.format("world", context: context(before: "hello"), options: options), "world")
    }

    func testSmartSpacingWhenReplacingASelection() {
        let options = TextFormatter.Options(smartCapitalization: false, smartSpacing: true)
        let ctx = context(before: "hello", selected: "there")
        XCTAssertEqual(formatter.format("world", context: ctx, options: options), " world")
    }

    // MARK: - Smart capitalization

    func testSmartCapitalization() {
        let options = TextFormatter.Options(smartCapitalization: true, smartSpacing: false)
        let cases: [(String?, Bool?, String, String)] = [
            ("", nil, "hello there", "Hello there"),
            (nil, true, "hello there", "Hello there"),
            (nil, nil, "hello there", "hello there"),        // unknown -> leave alone
            ("Done. ", nil, "next thing", "Next thing"),
            ("Really? ", nil, "yes", "Yes"),
            ("Stop! ", nil, "go", "Go"),
            ("line one\n", nil, "second line", "Second line"),
            ("Hello there ", nil, "How are you", "how are you"),   // mid-sentence
            ("and then ", nil, "I went home", "I went home"),      // "I" is never lowered
            ("we use ", nil, "API keys", "API keys"),              // acronym kept
            ("Hello there. ", nil, "How are you", "How are you"),  // already a new sentence
        ]
        for (before, empty, input, expected) in cases {
            let ctx = context(before: before, empty: empty)
            XCTAssertEqual(formatter.format(input, context: ctx, options: options), expected, "before: \(before ?? "nil")")
        }
    }

    func testSmartCapitalizationDisabled() {
        let options = TextFormatter.Options(smartCapitalization: false, smartSpacing: false)
        XCTAssertEqual(formatter.format("hello", context: context(before: ""), options: options), "hello")
    }

    // MARK: - Voice commands

    func testVoiceCommands() {
        let options = TextFormatter.Options(smartCapitalization: false, smartSpacing: false, voiceCommands: true)
        let cases: [(String, String)] = [
            ("hello comma world", "hello, world"),
            ("hello period", "hello."),
            ("done full stop", "done."),
            ("what time is it question mark", "what time is it?"),
            ("watch out exclamation mark", "watch out!"),
            ("watch out exclamation point", "watch out!"),
            ("listen colon this", "listen: this"),
            ("one semicolon two", "one; two"),
            ("first line new line second line", "first line\nsecond line"),
            ("say this new paragraph then that", "say this\n\nthen that"),
            ("he said open quote hello close quote", "he said \u{201C}hello\u{201D}"),
            ("twenty dash five", "twenty \u{2014} five"),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(formatter.format(input, context: nil, options: options), expected, "input: \(input)")
        }
    }

    func testVoiceCommandsAreConservative() {
        let options = TextFormatter.Options(smartCapitalization: false, smartSpacing: false, voiceCommands: true)
        let cases: [String] = [
            "the period of time",
            "press the question mark key",
            "a comma is punctuation",
            "this dash is long",
        ]
        for input in cases {
            XCTAssertEqual(formatter.format(input, context: nil, options: options), input, "input: \(input)")
        }
    }

    func testVoiceCommandsDisabledLeavesWordsAlone() {
        let options = TextFormatter.Options(smartCapitalization: false, smartSpacing: false, voiceCommands: false)
        XCTAssertEqual(formatter.format("hello comma world", context: nil, options: options), "hello comma world")
    }

    func testVoiceCommandsCombineWithCapitalizationAndSpacing() {
        let options = TextFormatter.Options(smartCapitalization: true, smartSpacing: true, voiceCommands: true)
        let ctx = context(before: "Hello", empty: false)
        XCTAssertEqual(formatter.format("and goodbye period", context: ctx, options: options), " and goodbye.")
    }
}

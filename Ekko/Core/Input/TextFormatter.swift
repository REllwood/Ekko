import Foundation

/// Post-processing between the engine and the target app.
/// Pure and unit-tested: trimming, smart spacing/capitalization using `FocusContext`,
/// and optional spoken commands ("new line", "new paragraph", "comma", "period" ...).
struct TextFormatter: Sendable {
    struct Options: Sendable, Equatable {
        var smartCapitalization = true
        var smartSpacing = true
        var voiceCommands = false

        init(smartCapitalization: Bool = true, smartSpacing: Bool = true, voiceCommands: Bool = false) {
            self.smartCapitalization = smartCapitalization
            self.smartSpacing = smartSpacing
            self.voiceCommands = voiceCommands
        }
    }

    init() {}

    /// Characters after which we never insert a smart space.
    private static let noSpaceAfter: Set<Character> = ["(", "[", "{", "\"", "\u{201C}", "/", "-", "\u{2014}", "@", "#", "$"]
    /// Sentence terminators that make the next utterance a new sentence.
    private static let sentenceTerminators: Set<Character> = [".", "!", "?", ":", "\u{2026}"]
    /// Words that keep their capital "I" whatever the surrounding context is.
    private static let alwaysCapitalWords: Set<String> = ["i", "i'm", "i'll", "i've", "i'd"]

    func format(_ raw: String, context: FocusContext?, options: Options) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }

        text = Self.collapseSpaces(text)
        if options.voiceCommands {
            text = Self.applyVoiceCommands(text)
        }
        guard !text.isEmpty else { return "" }
        if options.smartCapitalization {
            text = Self.applyCapitalization(text, context: context)
        }
        if options.smartSpacing {
            text = Self.applyLeadingSpace(text, context: context)
        }
        return text
    }

    // MARK: - Whitespace

    /// Collapses runs of spaces/tabs into a single space while preserving newlines.
    static func collapseSpaces(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        var lastWasSpace = false
        for character in text {
            if character == " " || character == "\t" {
                if !lastWasSpace, !out.isEmpty, !(out.last?.isNewline ?? false) { out.append(" ") }
                lastWasSpace = true
            } else {
                if character.isNewline {
                    // Drop the space that may precede a newline.
                    while out.last == " " { out.removeLast() }
                }
                out.append(character)
                lastWasSpace = false
            }
        }
        return out
    }

    // MARK: - Smart spacing

    /// Prepends a single space when the caret sits immediately after a word character.
    /// `textBeforeCursor == nil` means "unknown" and never adds anything. When a selection is
    /// being replaced, `textBeforeCursor` already ends at the start of that selection, so the
    /// same rule covers the "replacing a selection" case.
    static func applyLeadingSpace(_ text: String, context: FocusContext?) -> String {
        guard let before = context?.textBeforeCursor, let last = before.last else { return text }
        guard !last.isWhitespace, !noSpaceAfter.contains(last) else { return text }
        guard let first = text.first, !first.isWhitespace else { return text }
        // Never push a space in front of punctuation the formatter itself produced.
        if first.isPunctuation || first.isSymbol, first != "\u{201C}", first != "\"" { return text }
        return " " + text
    }

    // MARK: - Smart capitalization

    static func applyCapitalization(_ text: String, context: FocusContext?) -> String {
        guard let first = text.first, first.isLetter else { return text }

        switch sentencePosition(context: context) {
        case .sentenceStart:
            guard first.isLowercase else { return text }
            return text.replacingCharacters(in: text.startIndex...text.startIndex, with: String(first).uppercased())
        case .midSentence:
            guard first.isUppercase, shouldLowercaseFirstWord(of: text) else { return text }
            return text.replacingCharacters(in: text.startIndex...text.startIndex, with: String(first).lowercased())
        case .unknown:
            return text
        }
    }

    enum SentencePosition: Equatable {
        case sentenceStart
        case midSentence
        case unknown
    }

    static func sentencePosition(context: FocusContext?) -> SentencePosition {
        guard let context else { return .unknown }
        guard let before = context.textBeforeCursor else {
            return context.isFieldEmpty == true ? .sentenceStart : .unknown
        }
        if before.isEmpty { return .sentenceStart }
        let trimmed = before.reversed().drop { $0 == " " || $0 == "\t" }
        guard let last = trimmed.first else { return .sentenceStart }
        if last.isNewline { return .sentenceStart }
        if sentenceTerminators.contains(last) { return .sentenceStart }
        return .midSentence
    }

    /// Conservative: only de-capitalise an ordinary lowercase word that the engine capitalised
    /// because it thought it was starting a sentence. Acronyms ("API"), "I"-forms and anything
    /// with an internal capital ("McDonald") are left alone.
    private static func shouldLowercaseFirstWord(of text: String) -> Bool {
        let firstWord = text.prefix { !$0.isWhitespace }
        let stripped = firstWord.filter { $0.isLetter || $0 == "'" || $0 == "\u{2019}" }
        guard stripped.count >= 1 else { return false }
        if alwaysCapitalWords.contains(stripped.lowercased()) { return false }
        // Second character capital -> acronym or camel case; leave it.
        let rest = stripped.dropFirst()
        if rest.contains(where: { $0.isUppercase }) { return false }
        return true
    }

    // MARK: - Voice commands

    enum CommandKind: Equatable {
        /// Attaches to the preceding word, space afterwards: . , ? ! : ;
        case punctuation
        /// Space before, none after.
        case openQuote
        /// None before, space after.
        case closeQuote
        /// Space on both sides.
        case spaced
        /// A hard break; surrounding spaces are dropped.
        case lineBreak
    }

    struct VoiceCommand: Equatable {
        let words: [String]
        let replacement: String
        let kind: CommandKind
    }

    /// Longest phrases first so "exclamation mark" wins over "mark".
    static let voiceCommandTable: [VoiceCommand] = [
        VoiceCommand(words: ["new", "paragraph"], replacement: "\n\n", kind: .lineBreak),
        VoiceCommand(words: ["new", "line"], replacement: "\n", kind: .lineBreak),
        VoiceCommand(words: ["exclamation", "mark"], replacement: "!", kind: .punctuation),
        VoiceCommand(words: ["exclamation", "point"], replacement: "!", kind: .punctuation),
        VoiceCommand(words: ["question", "mark"], replacement: "?", kind: .punctuation),
        VoiceCommand(words: ["full", "stop"], replacement: ".", kind: .punctuation),
        VoiceCommand(words: ["open", "quote"], replacement: "\u{201C}", kind: .openQuote),
        VoiceCommand(words: ["close", "quote"], replacement: "\u{201D}", kind: .closeQuote),
        VoiceCommand(words: ["semi", "colon"], replacement: ";", kind: .punctuation),
        VoiceCommand(words: ["semicolon"], replacement: ";", kind: .punctuation),
        VoiceCommand(words: ["period"], replacement: ".", kind: .punctuation),
        VoiceCommand(words: ["comma"], replacement: ",", kind: .punctuation),
        VoiceCommand(words: ["colon"], replacement: ":", kind: .punctuation),
        VoiceCommand(words: ["dash"], replacement: "\u{2014}", kind: .spaced),
    ]

    // Heuristic for "is this word a command or just a word?" — deliberately conservative.
    // A phrase is only replaced when
    //   1. it matches whole word tokens (case-insensitive) that carry no attached punctuation, and
    //   2. the token immediately BEFORE it is not a determiner-ish word that would make the phrase
    //      a noun ("the period of time", "a comma"), and
    //   3. the token immediately AFTER it is not a word that continues that noun phrase
    //      ("question mark key", "period of time").
    // Everything else ("hello comma world", "done period") is treated as a command.
    // Only determiners that MUST be followed by a noun are listed; demonstratives such as
    // "this"/"that" are not, because "say this new paragraph" is a perfectly normal command.
    private static let nounCueBefore: Set<String> = [
        "the", "a", "an", "of", "my", "your", "our", "their", "its", "each", "every", "another",
        "whole", "entire", "long", "short", "brief", "no", "any", "with",
    ]
    private static let nounCueAfter: Set<String> = [
        "of", "in", "on", "key", "keys", "mark", "marks", "button", "symbol", "symbols",
        "character", "characters", "sign", "signs", "was", "is", "are", "were", "separated",
        "delimited", "instead",
    ]

    static func applyVoiceCommands(_ text: String) -> String {
        let tokens = tokenize(text)
        var replacements: [Int: VoiceCommand] = [:]
        var consumed = Set<Int>()

        let wordIndices = tokens.indices.filter { !tokens[$0].isWhitespace }
        var position = 0
        while position < wordIndices.count {
            let startIndex = wordIndices[position]
            guard !consumed.contains(startIndex) else { position += 1; continue }
            var matched = false
            for command in voiceCommandTable {
                let count = command.words.count
                guard position + count <= wordIndices.count else { continue }
                var ok = true
                for offset in 0..<count {
                    let token = tokens[wordIndices[position + offset]]
                    guard token.isPlainWord, token.normalized == command.words[offset] else { ok = false; break }
                }
                guard ok else { continue }
                let previous = position > 0 ? tokens[wordIndices[position - 1]].normalized : nil
                let next = position + count < wordIndices.count ? tokens[wordIndices[position + count]].normalized : nil
                if let previous, nounCueBefore.contains(previous) { continue }
                if let next, nounCueAfter.contains(next) { continue }
                replacements[startIndex] = command
                for offset in 0..<count { consumed.insert(wordIndices[position + offset]) }
                position += count
                matched = true
                break
            }
            if !matched { position += 1 }
        }
        guard !replacements.isEmpty else { return text }
        return render(tokens: tokens, replacements: replacements, consumed: consumed)
    }

    private struct Token {
        var text: String
        var isWhitespace: Bool
        var normalized: String
        /// Only letters/apostrophes — a token like "period." is not treated as a command word.
        var isPlainWord: Bool
    }

    private static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        var currentIsWhitespace: Bool?
        func flush() {
            guard let isWhitespace = currentIsWhitespace, !current.isEmpty else { return }
            let normalized = current.lowercased()
            let plain = !isWhitespace && current.allSatisfy { $0.isLetter || $0 == "'" || $0 == "\u{2019}" }
            tokens.append(Token(text: current, isWhitespace: isWhitespace, normalized: normalized, isPlainWord: plain))
            current = ""
        }
        for character in text {
            let isWhitespace = character.isWhitespace
            if currentIsWhitespace != isWhitespace {
                flush()
                currentIsWhitespace = isWhitespace
            }
            current.append(character)
        }
        flush()
        return tokens
    }

    private static func render(tokens: [Token], replacements: [Int: VoiceCommand], consumed: Set<Int>) -> String {
        var out = ""
        var pendingSpace = false
        /// Set after an opening quote or a line break: the next gap must not become a space.
        var spaceSuppressed = false
        for index in tokens.indices {
            if let command = replacements[index] {
                switch command.kind {
                case .punctuation, .closeQuote:
                    out = trimTrailingSpaces(out)
                    out += command.replacement
                    pendingSpace = true
                    spaceSuppressed = false
                case .openQuote:
                    if !out.isEmpty, !(out.last?.isNewline ?? false) { out = trimTrailingSpaces(out) + " " }
                    out += command.replacement
                    pendingSpace = false
                    spaceSuppressed = true
                case .spaced:
                    if !out.isEmpty, !(out.last?.isNewline ?? false) { out = trimTrailingSpaces(out) + " " }
                    out += command.replacement
                    pendingSpace = true
                    spaceSuppressed = false
                case .lineBreak:
                    out = trimTrailingSpaces(out)
                    out += command.replacement
                    pendingSpace = false
                    spaceSuppressed = true
                }
                continue
            }
            if consumed.contains(index) { continue }
            let token = tokens[index]
            if token.isWhitespace {
                if token.text.contains(where: { $0.isNewline }) {
                    out = trimTrailingSpaces(out)
                    out += token.text
                    pendingSpace = false
                    spaceSuppressed = true
                } else if !spaceSuppressed, !out.isEmpty {
                    pendingSpace = true
                }
                continue
            }
            if pendingSpace, !out.isEmpty { out += " " }
            out += token.text
            pendingSpace = false
            spaceSuppressed = false
        }
        return trimTrailingSpaces(out)
    }

    private static func trimTrailingSpaces(_ text: String) -> String {
        var out = text
        while let last = out.last, last == " " || last == "\t" { out.removeLast() }
        return out
    }
}

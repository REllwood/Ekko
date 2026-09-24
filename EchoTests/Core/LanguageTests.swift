import XCTest
@testable import Echo

final class LanguageTests: XCTestCase {
    /// Whisper's classic list is 99 languages; large-v3 added Cantonese ("yue"), and WhisperKit's
    /// `Constants.languages` carries all 100 distinct codes. `Language.all` mirrors that set.
    func testContainsEveryWhisperLanguage() {
        XCTAssertEqual(Language.all.count, 100)
    }

    func testCodesAreUnique() {
        XCTAssertEqual(Set(Language.all.map(\.code)).count, Language.all.count)
    }

    func testEnglishNamesAreUnique() {
        XCTAssertEqual(Set(Language.all.map(\.englishName)).count, Language.all.count)
    }

    func testContainsExpectedCodes() {
        for code in ["en", "zh", "yue", "ja", "haw", "yi", "nn", "jw"] {
            XCTAssertNotNil(Language.named(code), "Missing \(code)")
        }
    }

    func testCantoneseIsDistinctFromMandarin() {
        XCTAssertEqual(Language.named("yue")?.englishName, "Cantonese")
        XCTAssertEqual(Language.named("zh")?.englishName, "Chinese")
    }

    func testSortedByEnglishName() {
        XCTAssertEqual(Language.all.map(\.englishName), Language.all.map(\.englishName).sorted())
    }

    func testEveryEntryIsPopulated() {
        for language in Language.all {
            XCTAssertFalse(language.code.isEmpty)
            XCTAssertFalse(language.englishName.isEmpty)
            XCTAssertFalse(language.nativeName.isEmpty)
            XCTAssertEqual(language.id, language.code)
            XCTAssertFalse(language.code.contains(" "))
            XCTAssertEqual(language.code, language.code.lowercased())
        }
    }

    func testCodesAreTwoOrThreeLetters() {
        for language in Language.all {
            XCTAssertTrue((2...3).contains(language.code.count), "Odd code: \(language.code)")
        }
    }

    func testAutoCodeIsNotALanguage() {
        XCTAssertNil(Language.named(Language.autoCode))
    }

    func testNamedHandlesNil() {
        XCTAssertNil(Language.named(nil))
        XCTAssertNil(Language.named("not-a-language"))
        XCTAssertEqual(Language.named("en")?.englishName, "English")
    }

    func testPopularLanguagesAllResolve() {
        XCTAssertEqual(Language.popular.count, Language.popularCodes.count)
        XCTAssertEqual(Language.popular.map(\.code), Language.popularCodes)
    }

    func testCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(Language.all)
        let decoded = try JSONDecoder().decode([Language].self, from: data)
        XCTAssertEqual(decoded, Language.all)
    }
}

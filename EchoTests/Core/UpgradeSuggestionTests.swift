import XCTest
@testable import Echo

final class UpgradeSuggestionTests: XCTestCase {
    private func model(_ id: ModelID) -> ModelDescriptor {
        ModelCatalog.descriptor(for: id)!
    }

    func testSmallModelOnPowerfulMacSuggestsTheRecommendation() {
        let suggestion = ModelRecommender.upgradeSuggestion(
            active: model("openai_whisper-base"),
            hardware: .m1MaxWith32GB,
            languageCode: nil,
            dismissedID: nil
        )
        XCTAssertEqual(suggestion?.id, "openai_whisper-large-v3-v20240930_turbo")
    }

    func testNoSuggestionWhenAlreadyUsingTheRecommendation() {
        XCTAssertNil(ModelRecommender.upgradeSuggestion(
            active: model("openai_whisper-large-v3-v20240930_turbo"),
            hardware: .m1MaxWith32GB,
            languageCode: nil,
            dismissedID: nil
        ))
    }

    func testNoSuggestionWhenActiveIsEquallyAccurate() {
        // Large v3 is as accurate as Turbo, just slower; that is a deliberate choice, not a gap.
        XCTAssertNil(ModelRecommender.upgradeSuggestion(
            active: model("openai_whisper-large-v3-v20240930"),
            hardware: .m1MaxWith32GB,
            languageCode: nil,
            dismissedID: nil
        ))
    }

    func testDismissedSuggestionStaysHidden() {
        XCTAssertNil(ModelRecommender.upgradeSuggestion(
            active: model("openai_whisper-base"),
            hardware: .m1MaxWith32GB,
            languageCode: nil,
            dismissedID: "openai_whisper-large-v3-v20240930_turbo"
        ))
    }

    func testNoSuggestionWithoutAnActiveModel() {
        XCTAssertNil(ModelRecommender.upgradeSuggestion(
            active: nil,
            hardware: .m1MaxWith32GB,
            languageCode: nil,
            dismissedID: nil
        ))
    }

    func testIntelNeverGetsPushedTowardsHeavyModels() {
        let suggestion = ModelRecommender.upgradeSuggestion(
            active: model("openai_whisper-tiny"),
            hardware: .intel16,
            languageCode: nil,
            dismissedID: nil
        )
        XCTAssertEqual(suggestion?.id, "openai_whisper-base")
    }

    func testEnglishOnlyModelWithAnotherLanguageSuggestsAMultilingualOne() {
        // Same accuracy tier, but it cannot transcribe French at all.
        let suggestion = ModelRecommender.upgradeSuggestion(
            active: model("distil-whisper_distil-large-v3_turbo_600MB"),
            hardware: .m2ProWith16GB,
            languageCode: "fr",
            dismissedID: nil
        )
        XCTAssertEqual(suggestion?.isEnglishOnly, false)
    }

    func testEnglishOnlyModelWithAutoDetectIsLeftAlone() {
        XCTAssertNil(ModelRecommender.upgradeSuggestion(
            active: model("distil-whisper_distil-large-v3_turbo_600MB"),
            hardware: .m2ProWith16GB,
            languageCode: "en",
            dismissedID: nil
        ))
    }
}

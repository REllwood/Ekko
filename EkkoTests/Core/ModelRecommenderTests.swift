import XCTest
@testable import Ekko

final class ModelRecommenderTests: XCTestCase {
    // MARK: - Recommendation per tier

    func testLimitedTierRecommendsBase() {
        let multilingual = ModelRecommender.recommendation(for: .intel16, preferEnglishOnly: false)
        XCTAssertEqual(multilingual.tier, .limited)
        XCTAssertEqual(multilingual.recommended.id, "openai_whisper-base")
        XCTAssertEqual(multilingual.alternatives.map(\.id), ["openai_whisper-small", "openai_whisper-tiny"])

        let english = ModelRecommender.recommendation(for: .intel16, preferEnglishOnly: true)
        XCTAssertEqual(english.recommended.id, "openai_whisper-base.en")
        XCTAssertEqual(english.alternatives.map(\.id), ["openai_whisper-small.en", "openai_whisper-tiny"])
    }

    func testCapableTierRecommendsACompressedTurbo() {
        let multilingual = ModelRecommender.recommendation(for: .m1With8GB, preferEnglishOnly: false)
        XCTAssertEqual(multilingual.tier, .capable)
        XCTAssertEqual(multilingual.recommended.id, "openai_whisper-large-v3-v20240930_turbo_632MB")
        XCTAssertEqual(multilingual.alternatives.map(\.id), ["openai_whisper-small", "openai_whisper-base"])

        let english = ModelRecommender.recommendation(for: .m1With8GB, preferEnglishOnly: true)
        XCTAssertEqual(english.recommended.id, "distil-whisper_distil-large-v3_turbo_600MB")
        XCTAssertEqual(english.alternatives.map(\.id), ["openai_whisper-small.en", "openai_whisper-base.en"])
    }

    func testStrongTierRecommendations() {
        let multilingual = ModelRecommender.recommendation(for: .m2ProWith16GB, preferEnglishOnly: false)
        XCTAssertEqual(multilingual.tier, .strong)
        XCTAssertEqual(multilingual.recommended.id, "openai_whisper-large-v3-v20240930_turbo_632MB")
        XCTAssertEqual(
            multilingual.alternatives.map(\.id),
            ["openai_whisper-large-v3-v20240930_turbo", "openai_whisper-small"]
        )

        let english = ModelRecommender.recommendation(for: .m2ProWith16GB, preferEnglishOnly: true)
        XCTAssertEqual(english.recommended.id, "distil-whisper_distil-large-v3_turbo_600MB")
        XCTAssertEqual(
            english.alternatives.map(\.id),
            [
                "openai_whisper-large-v3-v20240930_turbo_632MB",
                "openai_whisper-large-v3-v20240930_turbo",
                "openai_whisper-small.en",
            ]
        )
    }

    func testExceptionalTierRecommendsFullTurbo() {
        let multilingual = ModelRecommender.recommendation(for: .m1MaxWith32GB, preferEnglishOnly: false)
        XCTAssertEqual(multilingual.tier, .exceptional)
        XCTAssertEqual(multilingual.recommended.id, "openai_whisper-large-v3-v20240930_turbo")
        XCTAssertEqual(
            multilingual.alternatives.map(\.id),
            ["openai_whisper-large-v3-v20240930", "openai_whisper-large-v3-v20240930_turbo_632MB"]
        )

        let english = ModelRecommender.recommendation(for: .m1MaxWith32GB, preferEnglishOnly: true)
        XCTAssertEqual(english.recommended.id, "openai_whisper-large-v3-v20240930_turbo")
        XCTAssertEqual(english.alternatives.first?.id, "distil-whisper_distil-large-v3_turbo_600MB")
    }

    func testEveryTierAndLanguagePairProducesUsableCopy() {
        let machines: [HardwareProfile] = [.intel16, .m1With8GB, .m2ProWith16GB, .m1MaxWith32GB]
        for machine in machines {
            for english in [true, false] {
                let advice = ModelRecommender.recommendation(for: machine, preferEnglishOnly: english)
                XCTAssertFalse(advice.headline.isEmpty)
                XCTAssertFalse(advice.rationale.isEmpty)
                XCTAssertTrue(
                    advice.rationale.contains(machine.chipName),
                    "Rationale should name the chip: \(advice.rationale)"
                )
                XCTAssertLessThanOrEqual(
                    advice.recommended.minimumMemoryGB, machine.memoryGB,
                    "Recommended \(advice.recommended.id) needs more memory than \(machine.chipName) has"
                )
                for alternative in advice.alternatives {
                    XCTAssertLessThanOrEqual(alternative.minimumMemoryGB, machine.memoryGB)
                    XCTAssertNotEqual(alternative.id, advice.recommended.id)
                }
                if english {
                    XCTAssertTrue(
                        advice.recommended.isEnglishOnly || advice.tier == .exceptional,
                        "English users should get an English model below the top tier"
                    )
                }
            }
        }
    }

    func testRecommendationIsDeterministic() {
        let first = ModelRecommender.recommendation(for: .m2ProWith16GB, preferEnglishOnly: false)
        let second = ModelRecommender.recommendation(for: .m2ProWith16GB, preferEnglishOnly: false)
        XCTAssertEqual(first, second)
    }

    // MARK: - Suitability of every catalog model

    func testSuitabilityOnM1With8GB() {
        assertSuitability(
            on: .m1With8GB,
            expected: [
                "openai_whisper-tiny": .good,
                "openai_whisper-base.en": .good,
                "openai_whisper-base": .great,
                "openai_whisper-small.en": .good,
                "openai_whisper-small": .great,
                "distil-whisper_distil-large-v3_turbo_600MB": .good,
                "openai_whisper-large-v3-v20240930_turbo_632MB": .recommended,
                "openai_whisper-large-v3-v20240930_turbo": .notRecommended,
                "openai_whisper-large-v3-v20240930": .notRecommended,
            ]
        )
    }

    func testSuitabilityOnM2ProWith16GB() {
        assertSuitability(
            on: .m2ProWith16GB,
            expected: [
                "openai_whisper-tiny": .good,
                "openai_whisper-base.en": .good,
                "openai_whisper-base": .good,
                "openai_whisper-small.en": .good,
                "openai_whisper-small": .great,
                "distil-whisper_distil-large-v3_turbo_600MB": .good,
                "openai_whisper-large-v3-v20240930_turbo_632MB": .recommended,
                "openai_whisper-large-v3-v20240930_turbo": .great,
                "openai_whisper-large-v3-v20240930": .good,
            ]
        )
    }

    func testSuitabilityOnM1MaxWith32GB() {
        assertSuitability(
            on: .m1MaxWith32GB,
            expected: [
                "openai_whisper-tiny": .good,
                "openai_whisper-base.en": .good,
                "openai_whisper-base": .good,
                "openai_whisper-small.en": .good,
                "openai_whisper-small": .good,
                "distil-whisper_distil-large-v3_turbo_600MB": .good,
                "openai_whisper-large-v3-v20240930_turbo_632MB": .great,
                "openai_whisper-large-v3-v20240930_turbo": .recommended,
                "openai_whisper-large-v3-v20240930": .great,
            ]
        )
    }

    func testSuitabilityOnIntelWith16GB() {
        assertSuitability(
            on: .intel16,
            expected: [
                "openai_whisper-tiny": .great,
                "openai_whisper-base.en": .good,
                "openai_whisper-base": .recommended,
                "openai_whisper-small.en": .slow,
                "openai_whisper-small": .great,
                "distil-whisper_distil-large-v3_turbo_600MB": .notRecommended,
                "openai_whisper-large-v3-v20240930_turbo_632MB": .notRecommended,
                "openai_whisper-large-v3-v20240930_turbo": .notRecommended,
                "openai_whisper-large-v3-v20240930": .notRecommended,
            ]
        )
    }

    func testEnglishPreferenceMovesTheRecommendedBadge() {
        let distil = ModelCatalog.descriptor(for: "distil-whisper_distil-large-v3_turbo_600MB")
        XCTAssertNotNil(distil)
        guard let distil else { return }
        XCTAssertEqual(
            ModelRecommender.suitability(of: distil, on: .m2ProWith16GB, preferEnglishOnly: true),
            .recommended
        )
        XCTAssertEqual(ModelRecommender.suitability(of: distil, on: .m2ProWith16GB), .good)
    }

    func testModelsThatDoNotFitAreNeverRecommended() {
        for model in ModelCatalog.all where model.minimumMemoryGB > HardwareProfile.m1With8GB.memoryGB {
            XCTAssertEqual(ModelRecommender.suitability(of: model, on: .m1With8GB), .notRecommended, model.id)
        }
    }

    // MARK: - Realtime factor

    func testRealtimeFactorScalesWithTier() {
        guard let tiny = ModelCatalog.descriptor(for: "openai_whisper-tiny") else {
            return XCTFail("Missing tiny model")
        }
        XCTAssertEqual(ModelRecommender.estimatedRealtimeFactor(of: tiny, on: .m1MaxWith32GB), 60, accuracy: 0.001)
        XCTAssertEqual(ModelRecommender.estimatedRealtimeFactor(of: tiny, on: .m2ProWith16GB), 36, accuracy: 0.001)
        XCTAssertEqual(ModelRecommender.estimatedRealtimeFactor(of: tiny, on: .m1With8GB), 21, accuracy: 0.001)
        XCTAssertEqual(ModelRecommender.estimatedRealtimeFactor(of: tiny, on: .intel16), 4.8, accuracy: 0.001)
    }

    func testFasterModelsScoreHigherOnTheSameMac() {
        let sorted = ModelCatalog.all.sorted {
            ModelRecommender.estimatedRealtimeFactor(of: $0, on: .m1MaxWith32GB)
                > ModelRecommender.estimatedRealtimeFactor(of: $1, on: .m1MaxWith32GB)
        }
        XCTAssertEqual(sorted.first?.id, "openai_whisper-tiny")
        XCTAssertEqual(sorted.last?.id, "openai_whisper-large-v3-v20240930")
    }

    func testEveryCatalogEntryHasAPositiveFactorOnEveryMac() {
        for machine in [HardwareProfile.intel16, .m1With8GB, .m2ProWith16GB, .m1MaxWith32GB] {
            for model in ModelCatalog.all {
                XCTAssertGreaterThan(ModelRecommender.estimatedRealtimeFactor(of: model, on: machine), 0, model.id)
            }
        }
    }

    // MARK: - Helpers

    private func assertSuitability(
        on hardware: HardwareProfile,
        expected: [ModelID: ModelSuitability],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(expected.count, ModelCatalog.all.count, "Cover every catalog model", file: file, line: line)
        for model in ModelCatalog.all {
            guard let want = expected[model.id] else {
                XCTFail("No expectation for \(model.id)", file: file, line: line)
                continue
            }
            XCTAssertEqual(
                ModelRecommender.suitability(of: model, on: hardware), want,
                "\(model.id) on \(hardware.chipName)", file: file, line: line
            )
        }
    }
}

import XCTest
@testable import Ekko

/// Integrity of the curated catalog, and a sweep showing the recommender only ever points at
/// something the catalog can actually download.
final class ModelCatalogTests: XCTestCase {
    func testIdsAndNamesAreUnique() {
        let ids = ModelCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        let names = ModelCatalog.all.map(\.displayName)
        XCTAssertEqual(Set(names).count, names.count)
    }

    func testEveryEntryIsSane() {
        for model in ModelCatalog.all {
            XCTAssertFalse(model.id.isEmpty)
            XCTAssertFalse(model.id.contains("/"), "ids are folder names inside the repo: \(model.id)")
            XCTAssertEqual(model.id, model.id.trimmingCharacters(in: .whitespacesAndNewlines))
            XCTAssertFalse(model.displayName.isEmpty, model.id)
            XCTAssertFalse(model.summary.isEmpty, model.id)
            XCTAssertTrue((50_000_000...5_000_000_000).contains(model.sizeBytes), "\(model.id): \(model.sizeBytes) bytes")
            XCTAssertTrue((1...5).contains(model.accuracy), model.id)
            XCTAssertTrue((1...5).contains(model.speed), model.id)
            XCTAssertTrue([4, 8, 16, 32, 64].contains(model.minimumMemoryGB), model.id)
            XCTAssertEqual(ModelCatalog.descriptor(for: model.id), model)
        }
    }

    func testEnglishOnlyEntriesSayWhatTheyAre() {
        for model in ModelCatalog.all {
            XCTAssertEqual(model.isEnglishOnly, model.displayName.contains("English"), model.id)
            if model.isEnglishOnly {
                XCTAssertTrue(model.id.hasSuffix(".en") || model.family == .distilWhisper, model.id)
            }
        }
    }

    func testCatalogRunsFromSmallestToLargest() {
        // "Ordered from smallest to largest": neither accuracy nor the memory needed goes down.
        for (smaller, larger) in zip(ModelCatalog.all, ModelCatalog.all.dropFirst()) {
            XCTAssertLessThanOrEqual(smaller.accuracy, larger.accuracy, "\(smaller.id) before \(larger.id)")
            XCTAssertLessThanOrEqual(smaller.minimumMemoryGB, larger.minimumMemoryGB, "\(smaller.id) before \(larger.id)")
        }
    }

    func testFallbackIsAMultilingualCatalogEntry() {
        let fallback = ModelCatalog.descriptor(for: ModelCatalog.fallbackID)
        XCTAssertNotNil(fallback)
        XCTAssertEqual(fallback?.isEnglishOnly, false)
    }

    func testEveryLanguageHasAModelThatCanTranscribeIt() {
        XCTAssertTrue(ModelCatalog.all.contains { !$0.isEnglishOnly })
        XCTAssertTrue(ModelCatalog.all.contains { $0.isEnglishOnly })
        for language in Language.all {
            XCTAssertNotNil(Language.named(language.code), language.code)
            XCTAssertTrue(ModelCatalog.all.contains { !$0.isEnglishOnly || language.code == "en" }, language.code)
        }
    }

    func testDescriptorLookupRejectsUnknownIds() {
        XCTAssertNil(ModelCatalog.descriptor(for: ""))
        XCTAssertNil(ModelCatalog.descriptor(for: "openai_whisper-huge"))
        XCTAssertNil(ModelCatalog.descriptor(for: "OPENAI_WHISPER-BASE"))
    }

    func testSizeLabels() {
        XCTAssertEqual(ModelCatalog.descriptor(for: "openai_whisper-tiny")?.sizeLabel, "77 MB")
        XCTAssertEqual(ModelCatalog.descriptor(for: "openai_whisper-large-v3-v20240930_turbo")?.sizeLabel, "1.6 GB")
    }

    // MARK: - Recommender sweep

    /// Every chip class and architecture over a wide range of memory sizes, including Macs too
    /// small for any model.
    private var machines: [HardwareProfile] {
        var machines: [HardwareProfile] = []
        for memory in [1, 2, 4, 8, 12, 16, 18, 24, 32, 36, 48, 64, 96, 128, 192] {
            machines.append(.make(chipName: "Intel(R) Core(TM) i9", architecture: .intel, chipClass: .unknown, generation: nil, memoryGB: memory))
            for chipClass in [HardwareProfile.ChipClass.base, .pro, .max, .ultra, .unknown] {
                machines.append(.make(
                    chipName: "Apple M\(chipClass == .unknown ? "" : "3 \(chipClass.rawValue)")",
                    architecture: .appleSilicon, chipClass: chipClass,
                    generation: chipClass == .unknown ? nil : 3, memoryGB: memory
                ))
            }
        }
        return machines
    }

    func testTheRecommenderOnlyPointsAtCatalogEntries() {
        let catalogIDs = Set(ModelCatalog.all.map(\.id))
        for machine in machines {
            for english in [true, false] {
                let advice = ModelRecommender.recommendation(for: machine, preferEnglishOnly: english)
                let label = "\(machine.summary), english: \(english)"
                XCTAssertTrue(catalogIDs.contains(advice.recommended.id), label)
                XCTAssertEqual(ModelCatalog.descriptor(for: advice.recommended.id), advice.recommended, label)
                for alternative in advice.alternatives {
                    XCTAssertTrue(catalogIDs.contains(alternative.id), label)
                    XCTAssertNotEqual(alternative.id, advice.recommended.id, label)
                }
                XCTAssertEqual(Set(advice.alternatives.map(\.id)).count, advice.alternatives.count, label)
                if machine.memoryGB >= 4 {
                    XCTAssertLessThanOrEqual(advice.recommended.minimumMemoryGB, machine.memoryGB, label)
                }
            }
        }
    }

    func testEveryLanguageIsRecommendedAModelThatSpeaksIt() {
        // Settings picks "English-only preferred" exactly when the language is English.
        for machine in machines {
            for code in [nil] + Language.all.map(\.code) {
                let advice = ModelRecommender.recommendation(for: machine, preferEnglishOnly: code == "en")
                if code != "en" {
                    XCTAssertFalse(
                        advice.recommended.isEnglishOnly,
                        "\(machine.summary) was offered \(advice.recommended.id) for \(code ?? "auto")"
                    )
                }
            }
        }
    }

    func testEverySuitabilityBadgeIsDefinedForEveryModel() {
        for machine in machines {
            for model in ModelCatalog.all {
                let badge = ModelRecommender.suitability(of: model, on: machine)
                XCTAssertFalse(badge.label.isEmpty)
                if model.minimumMemoryGB > machine.memoryGB {
                    XCTAssertEqual(badge, .notRecommended, "\(model.id) on \(machine.summary)")
                }
            }
        }
    }
}

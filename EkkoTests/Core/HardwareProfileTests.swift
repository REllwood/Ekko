import XCTest
@testable import Ekko

final class HardwareProfileTests: XCTestCase {
    // MARK: - Chip name parsing

    func testParsesAppleSiliconBaseChips() {
        let m1 = HardwareProfile.parse(chipName: "Apple M1")
        XCTAssertEqual(m1?.architecture, .appleSilicon)
        XCTAssertEqual(m1?.chipClass, .base)
        XCTAssertEqual(m1?.generation, 1)
        XCTAssertEqual(m1?.hasNeuralEngine, true)

        XCTAssertEqual(HardwareProfile.parse(chipName: "Apple M4")?.generation, 4)
        XCTAssertEqual(HardwareProfile.parse(chipName: "Apple M4")?.chipClass, .base)
    }

    func testParsesAppleSiliconClasses() {
        XCTAssertEqual(HardwareProfile.parse(chipName: "Apple M2 Pro")?.chipClass, .pro)
        XCTAssertEqual(HardwareProfile.parse(chipName: "Apple M1 Max")?.chipClass, .max)
        XCTAssertEqual(HardwareProfile.parse(chipName: "Apple M3 Ultra")?.chipClass, .ultra)
        XCTAssertEqual(HardwareProfile.parse(chipName: "Apple M2 Pro")?.generation, 2)
        XCTAssertEqual(HardwareProfile.parse(chipName: "Apple M1 Max")?.generation, 1)
        XCTAssertEqual(HardwareProfile.parse(chipName: "Apple M3 Ultra")?.generation, 3)
    }

    func testParsingIsCaseAndSpacingInsensitive() {
        XCTAssertEqual(HardwareProfile.parse(chipName: "apple m1 max")?.chipClass, .max)
        XCTAssertEqual(HardwareProfile.parse(chipName: "APPLE M2 ULTRA")?.chipClass, .ultra)
    }

    func testParsesIntel() {
        let intel = HardwareProfile.parse(chipName: "Intel(R) Core(TM) i7-9750H CPU @ 2.60GHz")
        XCTAssertEqual(intel?.architecture, .intel)
        XCTAssertEqual(intel?.chipClass, .unknown)
        XCTAssertNil(intel?.generation)
        XCTAssertEqual(intel?.hasNeuralEngine, false)
    }

    func testParsesUnlabelledAppleSilicon() {
        let generic = HardwareProfile.parse(chipName: "Apple Silicon")
        XCTAssertEqual(generic?.architecture, .appleSilicon)
        XCTAssertEqual(generic?.chipClass, .unknown)
        XCTAssertNil(generic?.generation)
        XCTAssertEqual(generic?.hasNeuralEngine, true)
    }

    func testRejectsUnknownNames() {
        XCTAssertNil(HardwareProfile.parse(chipName: ""))
        XCTAssertNil(HardwareProfile.parse(chipName: "   "))
        XCTAssertNil(HardwareProfile.parse(chipName: "Some Other CPU"))
    }

    // MARK: - Performance tiers

    func testPerformanceTiers() {
        XCTAssertEqual(HardwareProfile.intel16.performanceTier, .limited)
        XCTAssertEqual(HardwareProfile.m1With8GB.performanceTier, .capable)
        XCTAssertEqual(HardwareProfile.m2ProWith16GB.performanceTier, .strong)
        XCTAssertEqual(HardwareProfile.m1MaxWith32GB.performanceTier, .exceptional)
    }

    func testIntelIsAlwaysLimitedEvenWithLotsOfMemory() {
        let bigIntel = HardwareProfile.make(
            chipName: "Intel(R) Xeon(R) W",
            architecture: .intel,
            chipClass: .unknown,
            generation: nil,
            memoryGB: 128
        )
        XCTAssertEqual(bigIntel.performanceTier, .limited)
    }

    func testBaseChipWithPlentyOfMemoryIsStrong() {
        let m2With16 = HardwareProfile.make(
            chipName: "Apple M2",
            architecture: .appleSilicon,
            chipClass: .base,
            generation: 2,
            memoryGB: 16
        )
        XCTAssertEqual(m2With16.performanceTier, .strong)
    }

    // MARK: - Live detection

    func testDetectReturnsUsableValues() {
        let profile = HardwareProfile.detect()
        XCTAssertFalse(profile.chipName.isEmpty)
        XCTAssertFalse(profile.modelIdentifier.isEmpty)
        XCTAssertGreaterThan(profile.memoryGB, 0)
        XCTAssertGreaterThan(profile.coreCount, 0)
        XCTAssertFalse(profile.summary.isEmpty)
    }
}

// MARK: - Fixtures

extension HardwareProfile {
    static func make(
        chipName: String,
        architecture: Architecture,
        chipClass: ChipClass,
        generation: Int?,
        memoryGB: Int,
        coreCount: Int = 8
    ) -> HardwareProfile {
        HardwareProfile(
            modelIdentifier: "TestMac1,1",
            chipName: chipName,
            architecture: architecture,
            chipClass: chipClass,
            chipGeneration: generation,
            memoryGB: memoryGB,
            coreCount: coreCount,
            hasNeuralEngine: architecture == .appleSilicon
        )
    }

    static let m1With8GB = make(
        chipName: "Apple M1", architecture: .appleSilicon, chipClass: .base, generation: 1, memoryGB: 8
    )
    static let m2ProWith16GB = make(
        chipName: "Apple M2 Pro", architecture: .appleSilicon, chipClass: .pro, generation: 2, memoryGB: 16, coreCount: 12
    )
    static let m1MaxWith32GB = make(
        chipName: "Apple M1 Max", architecture: .appleSilicon, chipClass: .max, generation: 1, memoryGB: 32, coreCount: 10
    )
    static let intel16 = make(
        chipName: "Intel(R) Core(TM) i7-9750H CPU @ 2.60GHz",
        architecture: .intel, chipClass: .unknown, generation: nil, memoryGB: 16, coreCount: 12
    )
}

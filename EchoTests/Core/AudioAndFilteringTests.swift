import XCTest
@testable import Echo

final class AudioLevelMeterTests: XCTestCase {
    func testSilenceMapsToZero() {
        XCTAssertEqual(AudioLevelMeter.normalized(rms: 0), 0)
    }

    func testFullScaleMapsToOne() {
        XCTAssertEqual(AudioLevelMeter.normalized(rms: 1), 1, accuracy: 0.001)
    }

    func testMappingIsMonotonicAndBounded() {
        var previous: Float = -1
        for rms in stride(from: Float(0), through: 1, by: 0.05) {
            let value = AudioLevelMeter.normalized(rms: rms)
            XCTAssertGreaterThanOrEqual(value, previous)
            XCTAssertTrue((0...1).contains(value))
            previous = value
        }
    }

    func testVeryQuietAudioStaysNearZero() {
        XCTAssertLessThan(AudioLevelMeter.normalized(rms: 0.0005), 0.1)
    }

    func testAttackIsFasterThanRelease() {
        var rising = AudioLevelMeter()
        rising.process(rms: 0.5, deltaTime: 0.05)
        let afterAttack = rising.level

        var falling = AudioLevelMeter()
        for _ in 0..<200 { falling.process(rms: 0.5, deltaTime: 0.05) }
        let settled = falling.level
        falling.process(rms: 0, deltaTime: 0.05)
        let dropped = settled - falling.level

        XCTAssertGreaterThan(afterAttack, dropped, "Levels should rise faster than they fall")
    }

    func testResetReturnsToZero() {
        var meter = AudioLevelMeter()
        meter.process(rms: 0.5, deltaTime: 0.1)
        XCTAssertGreaterThan(meter.level, 0)
        meter.reset()
        XCTAssertEqual(meter.level, 0)
    }
}

final class SampleAccumulatorTests: XCTestCase {
    func testDrainReturnsAndClears() {
        let accumulator = SampleAccumulator()
        accumulator.append([0.1, 0.2])
        accumulator.append([0.3])
        XCTAssertEqual(accumulator.count, 3)
        XCTAssertEqual(accumulator.drain(), [0.1, 0.2, 0.3])
        XCTAssertEqual(accumulator.count, 0)
        XCTAssertTrue(accumulator.drain().isEmpty)
    }

    func testResetDiscards() {
        let accumulator = SampleAccumulator()
        accumulator.append([1, 2, 3])
        accumulator.reset()
        XCTAssertEqual(accumulator.count, 0)
    }

    func testConcurrentAppendsAreNotLost() {
        let accumulator = SampleAccumulator()
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            accumulator.append(Array(repeating: 0.25, count: 10))
        }
        XCTAssertEqual(accumulator.count, 1000)
    }
}

final class HallucinationFilterTests: XCTestCase {
    func testDropsSegmentsTheModelItselfDoubts() {
        XCTAssertTrue(
            HallucinationFilter.isNoise(
                text: "Hello there",
                noSpeechProbability: 0.9,
                averageLogProbability: -1.4,
                nearSilence: false
            )
        )
    }

    func testKeepsConfidentSpeech() {
        XCTAssertFalse(
            HallucinationFilter.isNoise(
                text: "Hello there",
                noSpeechProbability: 0.1,
                averageLogProbability: -0.2,
                nearSilence: false
            )
        )
    }

    func testHighNoSpeechAloneIsNotEnough() {
        XCTAssertFalse(
            HallucinationFilter.isNoise(
                text: "Hello there",
                noSpeechProbability: 0.9,
                averageLogProbability: -0.3,
                nearSilence: false
            )
        )
    }

    func testDropsClassicSilencePhrasesOnlyWhenTheAudioWasSilent() {
        for phrase in ["Thank you.", "Thanks for watching!", "you", "Bye.", "Subtitles by the Amara.org community"] {
            XCTAssertTrue(
                HallucinationFilter.isNoise(
                    text: phrase,
                    noSpeechProbability: 0.2,
                    averageLogProbability: -0.3,
                    nearSilence: true
                ),
                "Expected \"\(phrase)\" to be filtered from silence"
            )
            XCTAssertFalse(
                HallucinationFilter.isNoise(
                    text: phrase,
                    noSpeechProbability: 0.2,
                    averageLogProbability: -0.3,
                    nearSilence: false
                ),
                "Expected \"\(phrase)\" to survive real audio"
            )
        }
    }

    func testKeepsRealSentencesEvenFromQuietAudio() {
        XCTAssertFalse(
            HallucinationFilter.isNoise(
                text: "Thank you for sending the contract over this morning.",
                noSpeechProbability: 0.2,
                averageLogProbability: -0.3,
                nearSilence: true
            )
        )
    }

    func testDropsSoundEventAnnotationsAtAnyVolume() {
        for marker in ["[BLANK_AUDIO]", "(smooth music)", "[MUSIC]", "(upbeat music playing)", "♪♪♪", "*coughs*"] {
            XCTAssertTrue(
                HallucinationFilter.isNoise(
                    text: marker,
                    noSpeechProbability: 0.1,
                    averageLogProbability: -0.2,
                    nearSilence: false
                ),
                "Expected \"\(marker)\" to be filtered"
            )
        }
    }

    func testKeepsDictatedTextThatMerelyContainsBrackets() {
        XCTAssertFalse(HallucinationFilter.isNonSpeechMarker("Send it to (see the attached note) and copy me."))
        XCTAssertFalse(HallucinationFilter.isNonSpeechMarker("Meet at 3 (the usual place)"))
    }

    func testEmptySegmentsCountAsNoise() {
        XCTAssertTrue(HallucinationFilter.isNonSpeechMarker(""))
        XCTAssertTrue(HallucinationFilter.isNonSpeechMarker("   "))
        XCTAssertTrue(HallucinationFilter.isNonSpeechMarker("..."))
    }

    func testNormalizeStripsPunctuationAndCase() {
        XCTAssertEqual(HallucinationFilter.normalize("  Thank   you!!  "), "thank you")
        XCTAssertEqual(HallucinationFilter.normalize("Bye-bye."), "bye bye")
        XCTAssertEqual(HallucinationFilter.normalize("♪♪♪"), "")
    }
}

final class AudioBufferTests: XCTestCase {
    func testDurationUsesSixteenKilohertz() {
        let buffer = AudioBuffer16k(samples: Array(repeating: 0, count: 16_000))
        XCTAssertEqual(buffer.duration, 1, accuracy: 0.0001)
    }

    func testRMSOfSilenceIsBelowTheSilenceThreshold() {
        let buffer = AudioBuffer16k(samples: Array(repeating: 0, count: 1600))
        XCTAssertLessThan(buffer.rms, HallucinationFilter.silenceRMS)
    }

    func testRMSOfSpeechLikeSignalIsAboveTheThreshold() {
        let samples = (0..<1600).map { Float(sin(Double($0) * 0.1)) * 0.2 }
        XCTAssertGreaterThan(AudioBuffer16k(samples: samples).rms, HallucinationFilter.silenceRMS)
    }

    func testAudibleDurationIgnoresABriefClickInSilence() {
        var samples = [Float](repeating: 0, count: 16_000)            // 1 s of silence
        for i in 4_000..<4_480 { samples[i] = 0.3 }                  // a 30 ms click
        XCTAssertLessThan(AudioBuffer16k(samples: samples).audibleDuration(threshold: 0.006), 0.1)
    }

    func testAudibleDurationCountsSustainedSound() {
        let tone = (0..<16_000).map { Float(sin(Double($0) * 0.1) * 0.05) }   // 1 s at ~0.035 RMS
        XCTAssertEqual(AudioBuffer16k(samples: tone).audibleDuration(threshold: 0.006), 1.0, accuracy: 0.03)
    }
}

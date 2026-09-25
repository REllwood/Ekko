import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Ekko

/// The dictation pipeline end to end, with fakes for the microphone, the engine, the inserter
/// and the permissions, a temporary model folder and history file, and a hand-driven clock.
/// `start()` is never called: it would install the real event tap and apply the login item.
@MainActor
final class DictationControllerTests: XCTestCase {
    private static let modelID: ModelID = "openai_whisper-base"
    private static let optionSpace = Hotkey(kind: .combo(
        keyCode: UInt16(kVK_Space), modifiers: NSEvent.ModifierFlags.option.rawValue
    ))

    /// Everything one controller needs, built fresh for each test.
    @MainActor
    private final class Harness {
        let settings: SettingsStore
        let permissions = PermissionScript()
        let modelManager: ModelManager
        let audio = FakeAudioCapture()
        let engine = FakeTranscriptionEngine()
        let hotkeys = HotkeyManager()
        let inserter = FakeTextInserter()
        let historyStore: HistoryStore
        let controller: DictationController
        var clock = Date(timeIntervalSinceReferenceDate: 100_000)

        init(defaults: UserDefaults, directory: URL, modelInstalled: Bool) throws {
            let modelsRoot = directory.appendingPathComponent("Models", isDirectory: true)
            if modelInstalled {
                try ModelFixtures.install(DictationControllerTests.modelID, under: modelsRoot)
            }
            settings = SettingsStore(defaults: defaults)
            settings.activeModelID = modelInstalled ? DictationControllerTests.modelID : nil
            modelManager = ModelManager(settings: settings, downloadBase: modelsRoot, downloader: FakeModelDownloader())
            historyStore = HistoryStore(directory: directory.appendingPathComponent("History", isDirectory: true))
            controller = DictationController(
                settings: settings,
                permissions: permissions.makeManager(),
                modelManager: modelManager,
                audio: audio,
                engine: engine,
                hotkeys: hotkeys,
                inserter: inserter,
                sounds: SoundPlayer(isEnabled: false),
                historyStore: historyStore
            )
            // Failures stay on screen until a test shortens this; the "inserted" tick is instant.
            controller.timing = DictationController.Timing(
                armDelay: 0, minimumToggleInterval: 0.4, insertedLinger: 0, failureLinger: 600
            )
            controller.now = { [unowned self] in self.clock }
        }

        var state: DictationState { controller.state }

        func advance(_ seconds: TimeInterval) {
            clock = clock.addingTimeInterval(seconds)
        }
    }

    private func makeHarness(modelInstalled: Bool = true) throws -> Harness {
        let defaults = TemporaryDefaults()
        let directory = try TemporaryDirectory("EkkoDictationTests")
        addTeardownBlock {
            defaults.remove()
            directory.remove()
        }
        let harness = try Harness(defaults: defaults.defaults, directory: directory.url, modelInstalled: modelInstalled)
        // Runs first (teardown blocks run last-in, first-out): ends any lingering tasks.
        addTeardownBlock { harness.controller.stop() }
        return harness
    }

    /// A harness whose model is already loaded, so starting opens the microphone at once.
    private func makeReadyHarness() async throws -> Harness {
        let h = try makeHarness()
        h.controller.preloadModelIfNeeded()
        await waitUntil("the model is loaded") { h.controller.isModelLoaded }
        return h
    }

    /// Records one complete dictation of `text`.
    private func dictate(_ text: String, with h: Harness) async {
        h.engine.result.text = text
        h.controller.startListening()
        XCTAssertEqual(h.state, .listening)
        h.controller.stopAndTranscribe()
        await waitUntil("the dictation finishes") { h.state == .idle }
    }

    // MARK: - The happy path

    func testTranscriptIsFormattedAndInsertedWithTheConfiguredMethod() async throws {
        let h = try await makeReadyHarness()
        h.settings.insertionMethod = .paste
        h.settings.restoreClipboardAfterPaste = false
        h.settings.languageCode = "en"
        h.settings.inputDeviceID = "USB-Mic-1"
        h.inserter.focusContext.textBeforeCursor = "Dear team."
        h.engine.result.text = "  thanks   for the update  "

        h.controller.startListening()
        XCTAssertEqual(h.state, .listening)
        XCTAssertEqual(h.audio.startRequests, ["USB-Mic-1"])
        XCTAssertTrue(h.hotkeys.swallowEscape, "Escape cancels while listening")

        h.controller.stopAndTranscribe()
        await waitUntil("the dictation finishes") { h.state == .idle }

        XCTAssertEqual(h.engine.transcriptions.count, 1)
        XCTAssertEqual(h.engine.transcriptions.first?.audio, h.audio.recording)
        XCTAssertEqual(h.engine.transcriptions.first?.options, TranscriptionOptions(languageCode: "en", task: .transcribe))
        XCTAssertEqual(h.inserter.insertions, [
            FakeTextInserter.Insertion(
                text: " Thanks for the update",
                context: h.inserter.focusContext,
                method: .paste,
                restoreClipboard: false
            ),
        ])
        XCTAssertFalse(h.hotkeys.swallowEscape)
        XCTAssertEqual(h.controller.listeningDuration, 0)
    }

    func testFormattingOptionsComeFromSettings() async throws {
        let h = try await makeReadyHarness()
        h.settings.smartCapitalization = false
        h.settings.smartSpacing = false
        h.settings.voiceCommandsEnabled = true
        h.settings.insertionMethod = .type
        h.settings.restoreClipboardAfterPaste = true
        h.inserter.focusContext.textBeforeCursor = "Hi."
        let raw = "hello new line world"

        await dictate(raw, with: h)

        let context = h.inserter.focusContext
        let custom = TextFormatter().format(
            raw, context: context,
            options: .init(smartCapitalization: false, smartSpacing: false, voiceCommands: true)
        )
        XCTAssertNotEqual(custom, TextFormatter().format(raw, context: context, options: .init()))
        XCTAssertEqual(h.inserter.insertions.map(\.text), [custom])
        XCTAssertEqual(h.inserter.insertions.first?.method, .type)
        XCTAssertEqual(h.inserter.insertions.first?.restoreClipboard, true)
    }

    func testStatesRunFromListeningThroughTranscribingAndInsertingBackToIdle() async throws {
        let h = try await makeReadyHarness()
        let transcribing = AsyncGate()
        let inserting = AsyncGate()
        h.engine.transcribeGate = transcribing
        h.inserter.gate = inserting
        XCTAssertEqual(h.state, .idle)

        h.controller.startListening()
        XCTAssertEqual(h.state, .listening)
        XCTAssertTrue(h.controller.isSessionActive)

        h.controller.stopAndTranscribe()
        XCTAssertEqual(h.state, .transcribing)
        XCTAssertFalse(h.controller.isSessionActive)
        XCTAssertEqual(h.audio.stopCount, 1)

        transcribing.open()
        await waitUntil("inserting") { h.state == .inserting }
        XCTAssertEqual(h.inserter.insertions.count, 1)

        inserting.open()
        await waitUntil("back to idle") { h.state == .idle }
    }

    func testTheInsertedTickLingersBeforeIdle() async throws {
        let h = try await makeReadyHarness()
        h.controller.timing.insertedLinger = 600
        h.controller.startListening()
        h.controller.stopAndTranscribe()
        await waitUntil("inserted") { h.inserter.insertions.count == 1 }
        await drainMainActor()
        XCTAssertEqual(h.state, .inserting, "the HUD keeps the tick up for insertedLinger")
    }

    // MARK: - Model loading

    func testStartingBeforeTheModelIsLoadedPreparesThenListens() async throws {
        let h = try makeHarness()
        let loading = AsyncGate()
        h.engine.loadGate = loading

        h.controller.startListening()
        XCTAssertEqual(h.state, .preparing)
        XCTAssertTrue(h.controller.isSessionActive)
        XCTAssertTrue(h.controller.isModelLoading)
        XCTAssertEqual(h.inserter.captureCount, 1, "focus is read before anything can steal it")
        await waitUntil("the engine is asked to load") { h.engine.loadRequests == [Self.modelID] }
        await drainMainActor()
        XCTAssertEqual(h.state, .preparing)
        XCTAssertEqual(h.audio.startRequests.count, 0, "the microphone waits for the model")

        loading.open()
        await waitUntil("listening") { h.state == .listening }
        XCTAssertTrue(h.controller.isModelLoaded)
        XCTAssertFalse(h.controller.isModelLoading)
        XCTAssertEqual(h.controller.modelLoadProgress, 1)
        XCTAssertEqual(h.audio.startRequests.count, 1)
    }

    func testLoadProgressIsMirroredAndALoadedModelIsNotLoadedTwice() async throws {
        let h = try makeHarness()
        let loading = AsyncGate()
        h.engine.loadGate = loading

        h.controller.preloadModelIfNeeded()
        XCTAssertTrue(h.controller.isModelLoading)
        await waitUntil("half-way progress") { h.controller.modelLoadProgress == 0.5 }
        h.controller.preloadModelIfNeeded() // Already loading.

        loading.open()
        await waitUntil("loaded") { h.controller.isModelLoaded }
        h.controller.preloadModelIfNeeded() // Already loaded.
        await drainMainActor()
        XCTAssertEqual(h.engine.loadRequests, [Self.modelID])
        XCTAssertEqual(h.controller.modelLoadProgress, 1)
    }

    func testReleasingWhileTheModelLoadsNeverOpensTheMicrophone() async throws {
        let h = try makeHarness()
        let loading = AsyncGate()
        h.engine.loadGate = loading

        h.controller.startListening()
        h.controller.stopAndTranscribe()
        XCTAssertEqual(h.state, .failed(.modelStillLoading))

        loading.open()
        await waitUntil("loaded") { h.controller.isModelLoaded }
        await drainMainActor()
        XCTAssertEqual(h.state, .failed(.modelStillLoading))
        XCTAssertTrue(h.audio.startRequests.isEmpty)
        XCTAssertTrue(h.engine.transcriptions.isEmpty)
    }

    func testAModelThatFailsToLoadFailsTheSession() async throws {
        let h = try makeHarness()
        h.engine.loadError = FakeError(message: "Corrupt weights.")

        h.controller.startListening()
        XCTAssertEqual(h.state, .preparing)
        await waitUntil("the load fails") { h.state == .failed(.modelLoadFailed("Corrupt weights.")) }
        XCTAssertFalse(h.controller.isModelLoaded)
        XCTAssertFalse(h.controller.isModelLoading)
        XCTAssertTrue(h.audio.startRequests.isEmpty)
    }

    // MARK: - Nothing heard

    func testTooShortRecordingIsNothingHeard() async throws {
        let h = try await makeReadyHarness()
        h.audio.recording = AudioFixtures.speech(seconds: 0.3)
        h.controller.startListening()
        h.controller.stopAndTranscribe()
        XCTAssertEqual(h.state, .failed(.nothingHeard))
        XCTAssertTrue(h.engine.transcriptions.isEmpty)
        XCTAssertTrue(h.inserter.insertions.isEmpty)
        XCTAssertFalse(h.hotkeys.swallowEscape)
    }

    func testTooQuietRecordingIsNothingHeard() async throws {
        let h = try await makeReadyHarness()
        h.audio.recording = AudioFixtures.speech(seconds: 2, amplitude: 0.003)
        XCTAssertLessThan(h.audio.recording.rms, DictationController.minimumRMS)
        h.controller.startListening()
        h.controller.stopAndTranscribe()
        XCTAssertEqual(h.state, .failed(.nothingHeard))
        XCTAssertTrue(h.engine.transcriptions.isEmpty)
    }

    func testAClickInSilenceIsNothingHeard() async throws {
        // Loud enough on average, but only 30 ms of it is sound.
        let h = try await makeReadyHarness()
        var samples = AudioFixtures.silence(seconds: 1).samples
        for index in 4_000..<4_480 { samples[index] = 0.3 }
        h.audio.recording = AudioBuffer16k(samples: samples)
        XCTAssertGreaterThan(h.audio.recording.rms, DictationController.minimumRMS)

        h.controller.startListening()
        h.controller.stopAndTranscribe()
        XCTAssertEqual(h.state, .failed(.nothingHeard))
        XCTAssertTrue(h.engine.transcriptions.isEmpty)
    }

    func testTheShortestAcceptedRecordingIsTranscribed() async throws {
        let h = try await makeReadyHarness()
        h.audio.recording = AudioFixtures.speech(seconds: DictationController.minimumDuration)
        await dictate("ok", with: h)
        XCTAssertEqual(h.engine.transcriptions.count, 1)
        XCTAssertEqual(h.inserter.insertions.count, 1)
    }

    func testAnEmptyTranscriptIsNothingHeard() async throws {
        let h = try await makeReadyHarness()
        h.engine.result.text = "  \n "
        h.controller.startListening()
        h.controller.stopAndTranscribe()
        await waitUntil("nothing heard") { h.state == .failed(.nothingHeard) }
        XCTAssertTrue(h.inserter.insertions.isEmpty)
        XCTAssertTrue(h.controller.history.isEmpty)
        XCTAssertNil(h.controller.lastTranscript)
    }

    func testAFailureReturnsToIdleAfterItsLinger() async throws {
        let h = try await makeReadyHarness()
        h.controller.timing.failureLinger = 0.05
        h.audio.recording = AudioFixtures.silence(seconds: 1)
        h.controller.startListening()
        h.controller.stopAndTranscribe()
        XCTAssertEqual(h.state, .failed(.nothingHeard))
        await waitUntil("back to idle") { h.state == .idle }

        // And the next dictation works.
        h.audio.recording = AudioFixtures.speech(seconds: 1)
        await dictate("second try", with: h)
        XCTAssertEqual(h.inserter.insertions.map(\.text), ["Second try"])
    }

    // MARK: - Failures

    func testEngineErrorFailsThenReturnsToIdle() async throws {
        let h = try await makeReadyHarness()
        h.controller.timing.failureLinger = 1
        h.engine.transcribeError = FakeError(message: "Decoder crashed.")

        h.controller.startListening()
        h.controller.stopAndTranscribe()
        await waitUntil("the failure shows") { h.state == .failed(.transcriptionFailed("Decoder crashed.")) }
        XCTAssertTrue(h.inserter.insertions.isEmpty)
        XCTAssertTrue(h.controller.history.isEmpty)

        await waitUntil("back to idle") { h.state == .idle }
    }

    func testTextLeftOnTheClipboardIsReportedAndStillRecorded() async throws {
        let h = try await makeReadyHarness()
        h.inserter.outcome = .leftOnClipboard
        h.engine.result.text = "keep these words"

        h.controller.startListening()
        h.controller.stopAndTranscribe()
        await waitUntil("the clipboard notice") { h.state == .failed(.insertionFailed("Copied to clipboard")) }
        XCTAssertEqual(h.state.isActive, false)
        XCTAssertEqual(h.controller.lastTranscript?.text, "Keep these words")
        XCTAssertEqual(h.controller.history.map(\.text), ["Keep these words"])
    }

    func testAMicrophoneThatWillNotStartFails() async throws {
        let h = try await makeReadyHarness()
        h.audio.startError = AudioCaptureError.deviceUnavailable("USB Mic")
        h.controller.startListening()
        XCTAssertEqual(h.state, .failed(.audioFailed("The microphone “USB Mic” is unavailable.")))
        XCTAssertFalse(h.hotkeys.swallowEscape)
    }

    func testDeniedMicrophoneFailsWithoutRecording() async throws {
        let h = try await makeReadyHarness()
        h.permissions.microphone = .denied
        h.controller.startListening()
        XCTAssertEqual(h.state, .failed(.microphoneDenied))
        XCTAssertTrue(h.audio.startRequests.isEmpty)
        XCTAssertEqual(h.inserter.captureCount, 0)
    }

    func testFirstDictationAsksForTheMicrophoneThenSaysItIsReady() async throws {
        let h = try await makeReadyHarness()
        h.permissions.microphone = .notDetermined
        h.permissions.answersMicrophonePrompt = true

        h.controller.startListening()
        XCTAssertEqual(h.state, .idle, "nothing starts while the prompt is up")
        await waitUntil("the microphone is ready") { h.state == .failed(.microphoneReady) }
        XCTAssertEqual(h.permissions.microphonePrompts, 1)
        XCTAssertTrue(h.audio.startRequests.isEmpty, "the key that triggered the prompt is long gone")
    }

    func testDecliningTheMicrophonePromptFails() async throws {
        let h = try await makeReadyHarness()
        h.permissions.microphone = .notDetermined
        h.permissions.answersMicrophonePrompt = false

        h.controller.startListening()
        h.controller.startListening() // A second press while the prompt is up asks only once.
        await waitUntil("denied") { h.state == .failed(.microphoneDenied) }
        XCTAssertEqual(h.permissions.microphonePrompts, 1)
    }

    func testNoInstalledModelFails() throws {
        let h = try makeHarness(modelInstalled: false)
        h.controller.startListening()
        XCTAssertEqual(h.state, .failed(.noModelInstalled))
        XCTAssertTrue(h.audio.startRequests.isEmpty)
        XCTAssertTrue(h.engine.loadRequests.isEmpty)
    }

    // MARK: - Cancel

    func testCancelWhileListeningDiscardsTheRecording() async throws {
        let h = try await makeReadyHarness()
        h.controller.startListening()
        h.controller.cancel()
        XCTAssertEqual(h.state, .idle)
        XCTAssertEqual(h.audio.cancelCount, 1)
        XCTAssertEqual(h.audio.stopCount, 0)
        XCTAssertFalse(h.hotkeys.swallowEscape)
        await drainMainActor()
        XCTAssertTrue(h.engine.transcriptions.isEmpty)
        XCTAssertTrue(h.inserter.insertions.isEmpty)
    }

    func testCancelWhilePreparingKeepsLoadingButNeverListens() async throws {
        let h = try makeHarness()
        let loading = AsyncGate()
        h.engine.loadGate = loading
        h.controller.startListening()
        h.controller.cancel()
        XCTAssertEqual(h.state, .idle)

        loading.open()
        await waitUntil("the model still loads for next time") { h.controller.isModelLoaded }
        await drainMainActor()
        XCTAssertEqual(h.state, .idle)
        XCTAssertTrue(h.audio.startRequests.isEmpty)
    }

    func testCancelDoesNotInterruptATranscription() async throws {
        let h = try await makeReadyHarness()
        let transcribing = AsyncGate()
        h.engine.transcribeGate = transcribing
        h.controller.startListening()
        h.controller.stopAndTranscribe()

        h.controller.cancel()
        XCTAssertEqual(h.state, .transcribing)
        transcribing.open()
        await waitUntil("finished") { h.state == .idle }
        XCTAssertEqual(h.inserter.insertions.count, 1)
    }

    func testCancelWhenIdleDoesNothing() throws {
        let h = try makeHarness()
        h.controller.cancel()
        XCTAssertEqual(h.state, .idle)
        XCTAssertEqual(h.audio.cancelCount, 0)
    }

    // MARK: - History

    func testHistoryRecordsAndSavesEachDictation() async throws {
        let h = try await makeReadyHarness()
        h.settings.languageCode = "de"
        h.engine.result.processingTime = 0.42

        await dictate("guten tag", with: h)

        let entry = try XCTUnwrap(h.controller.history.last)
        XCTAssertEqual(h.controller.history.count, 1)
        XCTAssertEqual(h.controller.lastTranscript, entry)
        XCTAssertEqual(entry.text, "Guten tag")
        XCTAssertEqual(entry.modelID, Self.modelID)
        XCTAssertEqual(entry.languageCode, "de")
        XCTAssertEqual(entry.audioDuration, h.audio.recording.duration, accuracy: 0.0001)
        XCTAssertEqual(entry.processingTime, 0.42, accuracy: 0.0001)
        XCTAssertEqual(entry.targetAppName, "TextEdit")
        XCTAssertEqual(entry.targetAppBundleID, "com.apple.TextEdit")

        await waitUntil("the history file is written") { h.historyStore.load().map(\.id) == [entry.id] }
    }

    func testTheDetectedLanguageIsRecordedWhenOnAuto() async throws {
        let h = try await makeReadyHarness()
        h.settings.languageCode = nil
        h.engine.result.detectedLanguageCode = "fr"
        await dictate("bonjour", with: h)
        XCTAssertEqual(h.controller.lastDetectedLanguageCode, "fr")
        XCTAssertEqual(h.controller.history.last?.languageCode, "fr")
    }

    func testWithHistoryOffNothingIsKept() async throws {
        let h = try await makeReadyHarness()
        h.settings.keepHistory = false
        await dictate("off the record", with: h)

        XCTAssertTrue(h.controller.history.isEmpty)
        XCTAssertEqual(h.controller.lastTranscript?.text, "Off the record", "the menu can still offer Copy")
        await drainMainActor()
        XCTAssertFalse(FileManager.default.fileExists(atPath: h.historyStore.fileURL.path))
    }

    func testClearHistoryEmptiesMemoryAndDisk() async throws {
        let h = try await makeReadyHarness()
        await dictate("first", with: h)
        await waitUntil("one entry saved") { h.historyStore.load().count == 1 }
        await dictate("second", with: h)
        await waitUntil("two entries saved") { h.historyStore.load().count == 2 }
        XCTAssertEqual(h.controller.history.map(\.text), ["First", "Second"])

        h.controller.clearHistory()
        XCTAssertTrue(h.controller.history.isEmpty)
        XCTAssertNil(h.controller.lastTranscript)
        await waitUntil("the file is removed") {
            !FileManager.default.fileExists(atPath: h.historyStore.fileURL.path)
        }
    }

    // MARK: - Activation modes through the hotkey

    func testHoldToTalkComboStartsOnPressAndStopsOnRelease() async throws {
        let h = try await makeReadyHarness()
        h.settings.hotkey = Self.optionSpace
        h.settings.activationMode = .holdToTalk

        h.controller.hotkeyPressed()
        XCTAssertEqual(h.state, .listening, "combos start at once")
        h.advance(2)
        h.controller.hotkeyReleased()
        XCTAssertEqual(h.state, .transcribing)
        await waitUntil("finished") { h.state == .idle }
        XCTAssertEqual(h.inserter.insertions.count, 1)
    }

    func testToggleModeStartsAndStopsOnPresses() async throws {
        let h = try await makeReadyHarness()
        h.settings.hotkey = Self.optionSpace
        h.settings.activationMode = .toggle

        h.controller.hotkeyPressed()
        h.advance(0.1)
        h.controller.hotkeyReleased()
        XCTAssertEqual(h.state, .listening, "releasing does nothing in toggle mode")

        h.advance(3)
        h.controller.hotkeyPressed()
        XCTAssertEqual(h.state, .transcribing)
        h.controller.hotkeyReleased()
        await waitUntil("finished") { h.state == .idle }
        XCTAssertEqual(h.inserter.insertions.count, 1)
    }

    func testAutoModeTapKeepsListeningUntilTheNextTap() async throws {
        let h = try await makeReadyHarness()
        h.settings.hotkey = Self.optionSpace
        h.settings.activationMode = .auto

        h.controller.hotkeyPressed()
        h.advance(0.1)
        h.controller.hotkeyReleased()
        XCTAssertEqual(h.state, .listening, "a tap leaves the microphone open")

        h.advance(4)
        h.controller.hotkeyPressed()
        XCTAssertEqual(h.state, .transcribing)
        h.advance(0.1)
        h.controller.hotkeyReleased()
        await waitUntil("finished") { h.state == .idle }
    }

    func testAutoModeHoldStopsOnRelease() async throws {
        let h = try await makeReadyHarness()
        h.settings.hotkey = Self.optionSpace
        h.settings.activationMode = .auto

        h.controller.hotkeyPressed()
        h.advance(ActivationResolver.holdThreshold + 0.5)
        h.controller.hotkeyReleased()
        XCTAssertEqual(h.state, .transcribing)
        await waitUntil("finished") { h.state == .idle }
    }

    func testModifierOnlyTriggerWaitsBeforeListening() async throws {
        let h = try await makeReadyHarness()
        h.settings.hotkey = Hotkey(kind: .modifier(.rightOption))
        h.controller.timing.armDelay = 0.05

        h.controller.hotkeyPressed()
        XCTAssertEqual(h.state, .idle, "nothing happens until the arm delay passes")
        XCTAssertEqual(h.inserter.captureCount, 0)
        await waitUntil("listening") { h.state == .listening }
        XCTAssertEqual(h.audio.startRequests.count, 1)
    }

    func testTypingWithTheTriggerHeldNeverOpensTheMicrophone() async throws {
        // ⌥3 for "#": the press is followed by another key inside the arm delay.
        let h = try await makeReadyHarness()
        h.settings.hotkey = Hotkey(kind: .modifier(.rightOption))

        h.controller.handleHotkey(.pressed)
        h.controller.handleHotkey(.interrupted)
        h.advance(0.05)
        h.controller.handleHotkey(.released)
        await drainMainActor()

        XCTAssertEqual(h.state, .idle)
        XCTAssertTrue(h.audio.startRequests.isEmpty)
        XCTAssertEqual(h.inserter.captureCount, 0)
    }

    func testAQuickTapInHoldToTalkNeverOpensTheMicrophone() async throws {
        let h = try await makeReadyHarness()
        h.settings.hotkey = Hotkey(kind: .modifier(.rightOption))
        h.settings.activationMode = .holdToTalk

        h.controller.handleHotkey(.pressed)
        h.advance(0.05)
        h.controller.handleHotkey(.released)
        await drainMainActor()

        XCTAssertEqual(h.state, .idle)
        XCTAssertTrue(h.audio.startRequests.isEmpty)
    }

    func testTypingSoonAfterStartingDiscardsTheSession() async throws {
        let h = try await makeReadyHarness()
        h.settings.hotkey = Hotkey(kind: .modifier(.rightOption))

        h.controller.handleHotkey(.pressed)
        await waitUntil("listening") { h.state == .listening }
        h.advance(0.2)
        h.controller.handleHotkey(.interrupted)
        XCTAssertEqual(h.state, .idle)
        XCTAssertEqual(h.audio.cancelCount, 1)
        XCTAssertTrue(h.engine.transcriptions.isEmpty)
    }

    func testAStrayKeyDuringALongHoldKeepsRecording() async throws {
        let h = try await makeReadyHarness()
        h.settings.hotkey = Hotkey(kind: .modifier(.rightOption))
        h.settings.activationMode = .holdToTalk

        h.controller.handleHotkey(.pressed)
        await waitUntil("listening") { h.state == .listening }
        h.advance(3)
        h.controller.handleHotkey(.interrupted)
        XCTAssertEqual(h.state, .listening)
        h.advance(1)
        h.controller.handleHotkey(.released)
        XCTAssertEqual(h.state, .transcribing)
        await waitUntil("finished") { h.state == .idle }
    }

    func testPressesAreIgnoredWhileBusy() async throws {
        let h = try await makeReadyHarness()
        h.settings.hotkey = Self.optionSpace
        h.settings.activationMode = .toggle
        let transcribing = AsyncGate()
        h.engine.transcribeGate = transcribing

        h.controller.hotkeyPressed()
        h.advance(2)
        h.controller.hotkeyPressed()
        XCTAssertEqual(h.state, .transcribing)
        h.controller.hotkeyPressed()
        h.controller.hotkeyReleased()
        XCTAssertEqual(h.state, .transcribing)
        XCTAssertEqual(h.audio.startRequests.count, 1)

        transcribing.open()
        await waitUntil("finished") { h.state == .idle }
    }

    // MARK: - HUD timer

    func testListeningDurationCountsUpForTheHUD() async throws {
        let h = try await makeReadyHarness()
        h.controller.startListening()
        XCTAssertEqual(h.controller.listeningDuration, 0)
        h.advance(7)
        // The HUD timer ticks every 0.1 s on the main run loop and reads the injected clock.
        await waitUntil("the elapsed time reaches the HUD") { h.controller.listeningDuration == 7 }

        h.controller.cancel()
        XCTAssertEqual(h.controller.listeningDuration, 0)
    }

    // MARK: - Menu-bar toggle

    func testToggleIgnoresADoubleClick() async throws {
        let h = try await makeReadyHarness()
        h.controller.toggle()
        XCTAssertEqual(h.state, .listening)
        h.advance(0.1)
        h.controller.toggle()
        XCTAssertEqual(h.state, .listening, "a stop this soon is an accidental double click")
        h.advance(1)
        h.controller.toggle()
        XCTAssertEqual(h.state, .transcribing)
        await waitUntil("finished") { h.state == .idle }
    }
}

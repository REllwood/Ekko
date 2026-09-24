import AppKit
import Foundation

/// Orchestrates one dictation: focus capture -> audio -> transcription -> formatting -> insertion.
/// Everything here is main-actor; the engine call is awaited off-main.
@Observable
@MainActor
final class DictationController {
    private(set) var state: DictationState = .idle
    private(set) var lastTranscript: TranscriptEntry?
    private(set) var history: [TranscriptEntry] = []

    /// Mirrors the engine so the UI can show "Loading model…" without touching the engine.
    private(set) var isModelLoaded = false
    private(set) var isModelLoading = false
    private(set) var modelLoadProgress: Double = 0
    /// Language the engine detected for the last transcription (when language is set to Auto).
    private(set) var lastDetectedLanguageCode: String?
    /// Seconds elapsed in the current listening session, updated ~10x/s for the HUD.
    private(set) var listeningDuration: TimeInterval = 0

    @ObservationIgnored let settings: SettingsStore
    @ObservationIgnored let permissions: PermissionsManager
    @ObservationIgnored let modelManager: ModelManager
    @ObservationIgnored let audio: AudioCaptureService
    @ObservationIgnored let engine: any TranscriptionEngine
    @ObservationIgnored let hotkeys: HotkeyManager
    @ObservationIgnored let inserter: TextInserter
    @ObservationIgnored let formatter: TextFormatter
    @ObservationIgnored let sounds: SoundPlayer
    @ObservationIgnored let historyStore: HistoryStore
    @ObservationIgnored let launchAtLogin: LaunchAtLogin

    /// Audio shorter than this (or quieter than `minimumRMS`) is treated as "nothing heard".
    static let minimumDuration: TimeInterval = 0.4
    static let minimumRMS: Float = 0.004
    /// How long the HUD keeps showing the "inserted" tick.
    static let insertedLinger: TimeInterval = 0.6
    /// How long a failure stays on screen before returning to idle.
    static let failureLinger: TimeInterval = 1.8

    @ObservationIgnored private var resolver = ActivationResolver()
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var focusContext: FocusContext?
    @ObservationIgnored private var sessionModelID: ModelID?
    @ObservationIgnored private var listeningStartedAt: Date?
    @ObservationIgnored private var listeningTimer: Timer?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var loadedModelID: ModelID?
    @ObservationIgnored private var reloadRequested = false
    @ObservationIgnored private var transcribeTask: Task<Void, Never>?
    @ObservationIgnored private var failureResetTask: Task<Void, Never>?
    @ObservationIgnored private var startAfterLoadTask: Task<Void, Never>?
    /// A modifier-only trigger (e.g. Right ⌥) waits this long before doing anything, so a press
    /// that turns out to be typing (⌥3 for "#") never opens the mic, plays a sound or shows UI.
    static let armDelay: TimeInterval = 0.15
    /// Clicks that stop a session this soon after it started are treated as an accidental double click.
    static let minimumToggleInterval: TimeInterval = 0.4
    /// Recordings need at least this much audible sound (not just a click or the start cue).
    static let minimumAudibleDuration: TimeInterval = 0.2
    static let audibleThreshold: Float = 0.006

    @ObservationIgnored private var armTask: Task<Void, Never>?
    @ObservationIgnored private var microphoneRequestTask: Task<Void, Never>?

    init(
        settings: SettingsStore,
        permissions: PermissionsManager,
        modelManager: ModelManager,
        audio: AudioCaptureService,
        engine: any TranscriptionEngine,
        hotkeys: HotkeyManager,
        inserter: TextInserter = TextInserter(),
        formatter: TextFormatter = TextFormatter(),
        sounds: SoundPlayer? = nil,
        historyStore: HistoryStore = HistoryStore(),
        launchAtLogin: LaunchAtLogin? = nil
    ) {
        self.settings = settings
        self.permissions = permissions
        self.modelManager = modelManager
        self.audio = audio
        self.engine = engine
        self.hotkeys = hotkeys
        self.inserter = inserter
        self.formatter = formatter
        self.sounds = sounds ?? SoundPlayer()
        self.historyStore = historyStore
        self.launchAtLogin = launchAtLogin ?? LaunchAtLogin()
    }

    // MARK: - Derived state

    /// True while a dictation is being prepared or is recording.
    var isSessionActive: Bool {
        state == .preparing || state.isListening
    }

    // MARK: - Lifecycle

    /// Registers for hotkey events and starts the tap when permitted. Safe to call repeatedly.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        hotkeys.onEvent = { [weak self] event in
            self?.handleHotkey(event)
        }
        hotkeys.onEscape = { [weak self] in
            self?.cancel()
        }
        hotkeys.hotkey = settings.hotkey
        sounds.isEnabled = settings.playSounds

        permissions.refresh()
        permissions.startMonitoring()
        launchAtLogin.startObserving(settings)

        loadHistory()
        startTapIfPossible()
        observeSettings()
        observePermissions()
        preloadModelIfNeeded()
        Log.dictation.info("DictationController started")
    }

    /// Stops the tap and any in-flight work. Used on termination and by tests.
    func stop() {
        cancel()
        transcribeTask?.cancel()
        failureResetTask?.cancel()
        startAfterLoadTask?.cancel()
        stopListeningTimer()
        hotkeys.stop()
        permissions.stopMonitoring()
        hasStarted = false
    }

    private func startTapIfPossible() {
        guard !hotkeys.isRunning else { return }
        do {
            try hotkeys.start()
        } catch HotkeyError.accessibilityNotGranted {
            Log.input.info("Hotkey tap waiting for Accessibility permission")
        } catch {
            Log.input.error("Hotkey tap failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func observeSettings() {
        withObservationTracking {
            _ = settings.hotkey
            _ = settings.activeModelID
            _ = settings.playSounds
            _ = modelManager.states
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.applySettings()
                self.observeSettings()
            }
        }
    }

    private func applySettings() {
        if hotkeys.hotkey != settings.hotkey {
            hotkeys.hotkey = settings.hotkey
            Log.input.info("Hotkey is now \(self.settings.hotkey.displayString, privacy: .public)")
        }
        sounds.isEnabled = settings.playSounds
        preloadModelIfNeeded()
    }

    private func observePermissions() {
        withObservationTracking {
            _ = permissions.accessibility
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.permissions.accessibility == .granted, !self.hotkeys.isRunning {
                    Log.input.info("Accessibility granted; installing the hotkey tap")
                    self.startTapIfPossible()
                }
                self.observePermissions()
            }
        }
    }

    // MARK: - Model lifecycle

    /// Loads the active model in the background if it isn't loaded yet.
    func preloadModelIfNeeded() {
        guard let model = modelManager.activeModel else {
            if isModelLoaded || loadedModelID != nil { unloadModel() }
            return
        }
        if loadedModelID == model.id, isModelLoaded { return }
        if isModelLoading {
            reloadRequested = true
            return
        }
        guard let folder = modelManager.folderURL(for: model.id) else {
            Log.dictation.error("No folder on disk for model \(model.id, privacy: .public)")
            return
        }
        loadModel(model, folder: folder)
    }

    private func loadModel(_ model: ModelDescriptor, folder: URL) {
        isModelLoading = true
        isModelLoaded = false
        modelLoadProgress = 0
        reloadRequested = false
        let engine = self.engine
        Log.dictation.info("Loading model \(model.id, privacy: .public)")

        let onProgress: @Sendable (Double) -> Void = { [weak self] progress in
            Task { @MainActor in
                self?.modelLoadProgress = min(max(progress, 0), 1)
            }
        }
        loadTask = Task { [weak self] in
            var failure: Error?
            do {
                try await engine.load(model: model, folder: folder, progress: onProgress)
            } catch {
                failure = error
            }
            guard let self else { return }
            self.finishModelLoad(model: model, failure: failure)
        }
    }

    private func finishModelLoad(model: ModelDescriptor, failure: Error?) {
        loadTask = nil
        isModelLoading = false
        if let failure {
            isModelLoaded = false
            loadedModelID = nil
            modelLoadProgress = 0
            Log.dictation.error("Model load failed: \(failure.localizedDescription, privacy: .public)")
            if state == .preparing {
                fail(.modelLoadFailed(failure.localizedDescription))
            }
        } else {
            isModelLoaded = true
            loadedModelID = model.id
            modelLoadProgress = 1
            Log.dictation.info("Model ready: \(model.id, privacy: .public)")
        }
        if reloadRequested {
            reloadRequested = false
            preloadModelIfNeeded()
        }
    }

    private func unloadModel() {
        let engine = self.engine
        loadedModelID = nil
        isModelLoaded = false
        modelLoadProgress = 0
        Task {
            await engine.unload()
        }
        Log.dictation.info("Model unloaded")
    }

    // MARK: - Hotkey entry points (mode logic lives in ActivationResolver)

    func hotkeyPressed() {
        handleHotkey(.pressed)
    }

    func hotkeyReleased() {
        handleHotkey(.released)
    }

    private func handleHotkey(_ event: HotkeyEvent) {
        if event == .pressed, state == .transcribing || state == .inserting {
            Log.dictation.debug("Hotkey ignored while busy")
            return
        }
        let action = resolver.resolve(
            event: event,
            mode: settings.activationMode,
            isSessionActive: isSessionActive,
            at: Date()
        )
        switch action {
        case .start:
            guard settings.hotkey.isModifierOnly else {
                startListening()
                return
            }
            armTask?.cancel()
            armTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.armDelay * 1_000_000_000))
                guard let self, !Task.isCancelled else { return }
                self.armTask = nil
                self.startListening()
            }
        case .stop:
            if disarm() { return } // A quick tap in hold-to-talk: nothing was started.
            stopAndTranscribe()
        case .cancel:
            if disarm() { return }
            Log.dictation.info("Hotkey was used to type; discarding the session it started")
            cancel()
        case .none:
            break
        }
    }

    /// Cancels a pending modifier-only start. Returns true if one was pending.
    @discardableResult
    private func disarm() -> Bool {
        guard let armTask else { return false }
        armTask.cancel()
        self.armTask = nil
        return true
    }

    // MARK: - Direct controls (menu bar, HUD, tests)

    /// Start if idle, stop-and-transcribe if listening.
    func toggle() {
        if isSessionActive {
            if let started = listeningStartedAt, Date().timeIntervalSince(started) < Self.minimumToggleInterval {
                Log.dictation.debug("Ignoring a stop right after start (double click)")
                return
            }
            stopAndTranscribe()
        } else {
            startListening()
        }
    }

    func startListening() {
        guard !state.isActive else { return }
        failureResetTask?.cancel()
        failureResetTask = nil
        if case .failed = state { state = .idle }

        permissions.refresh()
        if permissions.microphone == .notDetermined {
            // First dictation without onboarding: ask now. Don't start recording when the prompt is
            // answered: the key that triggered it has long been released (or is still held, which
            // the hold-to-talk logic can't see), so just say the mic is ready.
            guard microphoneRequestTask == nil else { return }
            resolver.reset()
            microphoneRequestTask = Task { [weak self] in
                guard let self else { return }
                let status = await self.permissions.requestMicrophone()
                self.microphoneRequestTask = nil
                guard !Task.isCancelled else { return }
                self.fail(status == .granted ? .microphoneReady : .microphoneDenied)
            }
            return
        }
        guard permissions.microphone == .granted else {
            fail(.microphoneDenied)
            return
        }
        guard let model = modelManager.activeModel else {
            fail(.noModelInstalled)
            return
        }

        // Focus must be read before anything can steal it (sounds, HUD, model loading).
        focusContext = inserter.captureFocusContext()
        sessionModelID = model.id
        hotkeys.swallowEscape = true

        if isModelLoaded, loadedModelID == model.id {
            openMicrophone()
            return
        }

        state = .preparing
        preloadModelIfNeeded()
        startAfterLoadTask?.cancel()
        startAfterLoadTask = Task { [weak self] in
            // A finished load can immediately start another (the user switched models meanwhile),
            // so wait until nothing is loading at all.
            while let task = self?.loadTask {
                await task.value
                if Task.isCancelled { return }
            }
            guard let self, self.state == .preparing, !Task.isCancelled else { return }
            guard self.isModelLoaded, let active = self.modelManager.activeModel, self.loadedModelID == active.id else {
                self.fail(.modelLoadFailed("Choose a model again in Echo's menu."))
                return
            }
            self.sessionModelID = active.id
            self.openMicrophone()
        }
    }

    private func openMicrophone() {
        sounds.play(.start)
        do {
            try audio.start(inputDeviceID: settings.inputDeviceID)
        } catch {
            fail(.audioFailed(error.localizedDescription))
            return
        }
        listeningStartedAt = Date()
        listeningDuration = 0
        state = .listening
        startListeningTimer()
        Log.dictation.info("Listening")
    }

    func stopAndTranscribe() {
        switch state {
        case .listening:
            break
        case .preparing:
            // Released before the model finished loading: nothing was recorded. The load keeps
            // going in the background so the next attempt starts instantly.
            Log.dictation.info("Released before the microphone opened")
            startAfterLoadTask?.cancel()
            startAfterLoadTask = nil
            resolver.reset()
            fail(.modelStillLoading)
            return
        default:
            return
        }

        stopListeningTimer()
        hotkeys.swallowEscape = false
        let buffer = audio.stop()
        let duration = buffer.duration
        let level = buffer.rms
        let audible = buffer.audibleDuration(threshold: Self.audibleThreshold)
        listeningDuration = 0

        // Whole-clip RMS alone lets a click or the start cue pass as speech; require some
        // sustained sound as well.
        guard duration >= Self.minimumDuration, level >= Self.minimumRMS, audible >= Self.minimumAudibleDuration else {
            Log.dictation.info("Nothing heard (\(duration, format: .fixed(precision: 2))s, rms \(level), audible \(audible, format: .fixed(precision: 2))s)")
            fail(.nothingHeard)
            return
        }

        sounds.play(.stop)
        state = .transcribing

        let options = TranscriptionOptions(languageCode: settings.languageCode, task: .transcribe)
        let modelID = sessionModelID ?? loadedModelID ?? (settings.activeModelID ?? "")
        let engine = self.engine
        transcribeTask?.cancel()
        transcribeTask = Task { [weak self] in
            do {
                let result = try await engine.transcribe(buffer, options: options)
                guard !Task.isCancelled, let self else { return }
                await self.handleTranscription(result, audioDuration: duration, modelID: modelID)
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.fail(.transcriptionFailed(error.localizedDescription))
            }
        }
    }

    private func handleTranscription(_ result: TranscriptionResult, audioDuration: TimeInterval, modelID: ModelID) async {
        lastDetectedLanguageCode = result.detectedLanguageCode

        let options = TextFormatter.Options(
            smartCapitalization: settings.smartCapitalization,
            smartSpacing: settings.smartSpacing,
            voiceCommands: settings.voiceCommandsEnabled
        )
        let text = formatter.format(result.text, context: focusContext, options: options)
        guard !text.isEmpty else {
            fail(.nothingHeard)
            return
        }

        let context = focusContext ?? FocusContext()
        state = .inserting

        let outcome = await inserter.insert(
            text,
            context: context,
            method: settings.insertionMethod,
            restoreClipboard: settings.restoreClipboardAfterPaste
        )

        record(text: text, audioDuration: audioDuration, processingTime: result.processingTime,
               languageCode: result.detectedLanguageCode ?? settings.languageCode, modelID: modelID)

        switch outcome {
        case .inserted(let method):
            Log.dictation.info("Inserted \(text.count, privacy: .public) characters via \(method.rawValue, privacy: .public)")
            focusContext = nil
            try? await Task.sleep(nanoseconds: UInt64(Self.insertedLinger * 1_000_000_000))
            if state == .inserting { state = .idle }
        case .leftOnClipboard:
            fail(.insertionFailed("Copied to clipboard"))
        }
    }

    /// Discards the current recording without transcribing.
    func cancel() {
        disarm()
        microphoneRequestTask?.cancel()
        switch state {
        case .preparing, .listening:
            startAfterLoadTask?.cancel()
            startAfterLoadTask = nil
            stopListeningTimer()
            audio.cancel()
            hotkeys.swallowEscape = false
            resolver.reset()
            focusContext = nil
            listeningDuration = 0
            state = .idle
            Log.dictation.info("Dictation cancelled")
        default:
            break
        }
    }

    func clearHistory() {
        history.removeAll()
        let store = historyStore
        Task.detached(priority: .utility) {
            store.clear()
        }
    }

    // MARK: - Failure handling

    private func fail(_ failure: DictationFailure) {
        stopListeningTimer()
        hotkeys.swallowEscape = false
        focusContext = nil
        listeningDuration = 0
        state = .failed(failure)
        if failure != .nothingHeard, failure != .microphoneReady { sounds.play(.error) }
        Log.dictation.error("Dictation failed: \(String(describing: failure), privacy: .public)")

        failureResetTask?.cancel()
        failureResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.failureLinger * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            if case .failed = self.state { self.state = .idle }
        }
    }

    // MARK: - History

    private func loadHistory() {
        guard settings.keepHistory else { return }
        let store = historyStore
        Task { [weak self] in
            let entries = await Task.detached(priority: .utility) { store.load() }.value
            guard let self, self.history.isEmpty else { return }
            self.history = entries
        }
    }

    private func record(text: String, audioDuration: TimeInterval, processingTime: TimeInterval, languageCode: String?, modelID: ModelID) {
        let entry = TranscriptEntry(
            text: text,
            audioDuration: audioDuration,
            processingTime: processingTime,
            languageCode: languageCode,
            modelID: modelID,
            targetAppName: focusContext?.appName,
            targetAppBundleID: focusContext?.appBundleID
        )
        lastTranscript = entry
        guard settings.keepHistory else { return }
        history.append(entry)
        if history.count > HistoryStore.maxEntries {
            history.removeFirst(history.count - HistoryStore.maxEntries)
        }
        let snapshot = history
        let store = historyStore
        Task.detached(priority: .utility) {
            store.save(snapshot)
        }
    }

    // MARK: - Listening timer

    private func startListeningTimer() {
        stopListeningTimer()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tickListening()
            }
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        listeningTimer = timer
    }

    private func tickListening() {
        guard state.isListening, let started = listeningStartedAt else { return }
        listeningDuration = Date().timeIntervalSince(started)
    }

    private func stopListeningTimer() {
        listeningTimer?.invalidate()
        listeningTimer = nil
        listeningStartedAt = nil
    }

    #if DEBUG
    /// Debug-only: drive the UI through a state without a microphone or a model (`--demo-state`).
    func debugSimulate(state: DictationState, listeningFor seconds: TimeInterval = 0, modelLoading progress: Double? = nil) {
        self.state = state
        listeningDuration = seconds
        isModelLoading = progress != nil
        modelLoadProgress = progress ?? 0
    }
    #endif
}

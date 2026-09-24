import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation

/// Captures microphone audio with AVAudioEngine, converts to 16 kHz mono Float32, accumulates it
/// for the current utterance, and publishes a smoothed level for the HUD.
///
/// Threading: the tap callback runs on the audio thread; it must append into a lock-protected
/// buffer and dispatch level updates to the main actor at <= 30 Hz.
@Observable
@MainActor
final class AudioCaptureService {
    private(set) var isCapturing = false
    /// Smoothed input level 0...1 for meters (perceptual, not raw RMS).
    private(set) var level: Float = 0
    /// Rolling window of recent levels (newest last) sized for the HUD's bar count.
    private(set) var levelHistory: [Float] = Array(repeating: 0, count: AudioCaptureService.historyLength)
    private(set) var availableInputs: [AudioInputDevice] = []
    /// Name of the device currently in use (for the HUD/menu).
    private(set) var activeInputName: String?

    static let historyLength = 24

    /// The only format the engine accepts.
    @ObservationIgnored
    static let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: AudioBuffer16k.sampleRate,
        channels: 1,
        interleaved: false
    )

    @ObservationIgnored private let accumulator = SampleAccumulator()
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var processor: AudioTapProcessor?
    /// UID requested by the caller; nil means "system default".
    @ObservationIgnored private var requestedDeviceID: String?
    @ObservationIgnored private var configurationObserver: NSObjectProtocol?
    @ObservationIgnored private var hardwareListener: AudioObjectPropertyListenerBlock?
    @ObservationIgnored private var listenedAddresses: [AudioObjectPropertyAddress] = []

    init() {
        availableInputs = AudioDeviceEnumerator.inputDevices()
        startListeningForDeviceChanges()
    }

    deinit {
        if let hardwareListener {
            for var address in listenedAddresses {
                AudioObjectRemovePropertyListenerBlock(
                    AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, hardwareListener
                )
            }
        }
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
    }

    #if DEBUG
    /// Debug-only: feed the meters without a microphone (`--demo-state listening`).
    func debugSimulate(levels: [Float]) {
        levelHistory = Array(levels.suffix(Self.historyLength))
        level = levels.last ?? 0
    }
    #endif

    /// Re-enumerates input devices (call on launch, on device-change notifications, and when the
    /// settings page appears).
    func refreshInputs() {
        availableInputs = AudioDeviceEnumerator.inputDevices()
        if !isCapturing {
            activeInputName = resolvedDevice(for: requestedDeviceID).map(\.name)
        }
    }

    /// Starts capturing. `inputDeviceID == nil` means the system default input.
    func start(inputDeviceID: String?) throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw AudioCaptureError.permissionDenied
        }
        if isCapturing { cancel() }

        requestedDeviceID = inputDeviceID
        accumulator.reset()
        resetLevels()
        refreshInputs()

        let engine = AVAudioEngine()
        do {
            try attachDevice(to: engine, uid: inputDeviceID)
            try installTap(on: engine)
            engine.prepare()
            try engine.start()
        } catch let error as AudioCaptureError {
            teardownEngine(engine)
            throw error
        } catch {
            teardownEngine(engine)
            throw AudioCaptureError.engineFailed(error.localizedDescription)
        }

        self.engine = engine
        isCapturing = true
        observeConfigurationChanges(of: engine)
        Log.audio.info("Capture started on \(self.activeInputName ?? "the default microphone", privacy: .public)")
    }

    /// Stops capturing and returns everything recorded since `start`.
    func stop() -> AudioBuffer16k {
        stopEngine()
        let samples = accumulator.drain()
        resetLevels()
        Log.audio.info("Capture stopped after \(String(format: "%.2f", Double(samples.count) / AudioBuffer16k.sampleRate), privacy: .public) s")
        return AudioBuffer16k(samples: samples)
    }

    /// Stops capturing and discards the audio.
    func cancel() {
        stopEngine()
        accumulator.reset()
        resetLevels()
    }

    // MARK: - Engine setup

    private func attachDevice(to engine: AVAudioEngine, uid: String?) throws {
        let input = engine.inputNode

        var device = resolvedDevice(for: uid)
        if uid != nil, device == nil {
            Log.audio.error("Microphone \(uid ?? "", privacy: .public) is not connected; falling back to the system default")
            device = resolvedDevice(for: nil)
        }
        guard let device else {
            throw AudioCaptureError.deviceUnavailable("No microphone is available.")
        }
        guard let audioUnit = input.audioUnit else {
            throw AudioCaptureError.engineFailed("The audio input unit is unavailable.")
        }

        var deviceID = device.deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw AudioCaptureError.deviceUnavailable(device.name)
        }
        activeInputName = device.name
    }

    private func installTap(on engine: AVAudioEngine) throws {
        guard let targetFormat = Self.targetFormat else {
            throw AudioCaptureError.engineFailed("Could not create the 16 kHz output format.")
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioCaptureError.deviceUnavailable(activeInputName ?? "Microphone")
        }
        guard let processor = AudioTapProcessor(
            inputFormat: format,
            outputFormat: targetFormat,
            accumulator: accumulator,
            levelSink: makeLevelSink()
        ) else {
            throw AudioCaptureError.engineFailed("Could not convert \(Int(format.sampleRate)) Hz audio to 16 kHz.")
        }

        self.processor = processor
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            processor.process(buffer)
        }
    }

    /// A main-actor hop for level updates, created here so the audio thread never touches `self`.
    private func makeLevelSink() -> @Sendable (Float) -> Void {
        { [weak self] value in
            Task { @MainActor in
                self?.publish(level: value)
            }
        }
    }

    private func publish(level value: Float) {
        guard isCapturing else { return }
        level = value
        var history = levelHistory
        if history.count >= Self.historyLength {
            history.removeFirst(history.count - Self.historyLength + 1)
        }
        history.append(value)
        levelHistory = history
    }

    private func resetLevels() {
        level = 0
        levelHistory = Array(repeating: 0, count: Self.historyLength)
    }

    private func stopEngine() {
        if let engine {
            teardownEngine(engine)
        }
        engine = nil
        processor = nil
        isCapturing = false
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
    }

    private func teardownEngine(_ engine: AVAudioEngine) {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
    }

    private func resolvedDevice(for uid: String?) -> (deviceID: AudioDeviceID, name: String)? {
        let id: AudioDeviceID?
        if let uid {
            id = AudioDeviceEnumerator.deviceID(forUID: uid)
        } else {
            id = AudioDeviceEnumerator.defaultInputDeviceID()
        }
        guard let id else { return nil }
        return (id, AudioDeviceEnumerator.name(of: id) ?? "Microphone")
    }

    // MARK: - Hardware changes

    private func startListeningForDeviceChanges() {
        let selectors = [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice]
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                self?.handleDeviceListChange()
            }
        }
        hardwareListener = listener
        listenedAddresses = selectors.map {
            AudioObjectPropertyAddress(
                mSelector: $0,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
        }
        for var address in listenedAddresses {
            AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, listener
            )
        }
    }

    private func handleDeviceListChange() {
        refreshInputs()
        guard isCapturing else { return }
        // The device we are recording from may have just been unplugged.
        if let uid = requestedDeviceID, AudioDeviceEnumerator.deviceID(forUID: uid) == nil {
            Log.audio.error("The selected microphone disappeared mid-recording; restarting on the default input")
            restartTapPreservingAudio(uid: nil)
        }
    }

    private func observeConfigurationChanges(of engine: AVAudioEngine) {
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleConfigurationChange()
            }
        }
    }

    private func handleConfigurationChange() {
        guard isCapturing else { return }
        Log.audio.info("The audio configuration changed; restarting the tap")
        restartTapPreservingAudio(uid: requestedDeviceID)
    }

    /// Rebuilds the tap for a new hardware format. Samples captured so far are kept, so `stop()`
    /// still returns the partial recording if this fails.
    private func restartTapPreservingAudio(uid: String?) {
        guard let engine else { return }
        teardownEngine(engine)
        do {
            try attachDevice(to: engine, uid: uid)
            try installTap(on: engine)
            engine.prepare()
            try engine.start()
            requestedDeviceID = uid
        } catch {
            Log.audio.error("Could not restart capture: \(error.localizedDescription, privacy: .public)")
            stopEngine()
        }
    }
}

// MARK: - Audio-thread plumbing

/// Lock-protected sample store shared between the audio thread and the main actor.
final class SampleAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []

    func append(_ newSamples: [Float]) {
        guard !newSamples.isEmpty else { return }
        lock.lock()
        samples.append(contentsOf: newSamples)
        lock.unlock()
    }

    func drain() -> [Float] {
        lock.lock()
        defer { samples = []; lock.unlock() }
        return samples
    }

    func reset() {
        lock.lock()
        samples = []
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return samples.count
    }
}

/// Converts tap buffers to 16 kHz mono, appends them, and reports a smoothed level at <= 30 Hz.
/// Lives entirely off the main actor; everything it touches is lock-protected.
final class AudioTapProcessor: @unchecked Sendable {
    private static let publishInterval: TimeInterval = 1.0 / 30

    private let lock = NSLock()
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private let ratio: Double
    private let accumulator: SampleAccumulator
    private let levelSink: @Sendable (Float) -> Void

    private var meter = AudioLevelMeter()
    private var lastBufferTime: TimeInterval = 0
    private var lastPublish: TimeInterval = 0

    init?(
        inputFormat: AVAudioFormat,
        outputFormat: AVAudioFormat,
        accumulator: SampleAccumulator,
        levelSink: @escaping @Sendable (Float) -> Void
    ) {
        guard inputFormat.sampleRate > 0,
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else { return nil }
        converter.sampleRateConverterQuality = AVAudioQuality.high.rawValue
        self.converter = converter
        self.outputFormat = outputFormat
        self.ratio = outputFormat.sampleRate / inputFormat.sampleRate
        self.accumulator = accumulator
        self.levelSink = levelSink
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0, let converted = convert(buffer) else { return }
        accumulator.append(converted)

        let now = Date.timeIntervalSinceReferenceDate
        let rms = Self.rms(of: converted)
        var valueToPublish: Float?

        lock.lock()
        let delta = lastBufferTime > 0 ? now - lastBufferTime : Double(converted.count) / outputFormat.sampleRate
        lastBufferTime = now
        let level = meter.process(rms: rms, deltaTime: delta)
        if now - lastPublish >= Self.publishInterval {
            lastPublish = now
            valueToPublish = level
        }
        lock.unlock()

        if let valueToPublish {
            levelSink(valueToPublish)
        }
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return nil }

        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }

        switch status {
        case .haveData, .inputRanDry:
            guard output.frameLength > 0, let channel = output.floatChannelData?[0] else { return nil }
            return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
        case .endOfStream:
            return nil
        case .error:
            Log.audio.error("Audio conversion failed: \(conversionError?.localizedDescription ?? "unknown", privacy: .public)")
            return nil
        @unknown default:
            return nil
        }
    }

    private static func rms(of samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var accumulator: Float = 0
        for sample in samples { accumulator += sample * sample }
        return (accumulator / Float(samples.count)).squareRoot()
    }
}

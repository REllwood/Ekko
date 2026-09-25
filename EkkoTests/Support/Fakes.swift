import Foundation
@testable import Ekko

// Stand-ins for the collaborators that would touch the network, the microphone, the frontmost
// app or the system permission database. All of them live on the main actor, so a test that
// resumes one knows its continuation runs on the main queue ahead of the test's next await.

/// Stands in for WhisperKit's downloader. Each `download` waits until the test finishes, fails
/// or cancels it.
@MainActor
final class FakeModelDownloader: ModelDownloading {
    private struct Pending {
        let downloadBase: URL
        let progress: @Sendable (ProgressSnapshot) -> Void
        let continuation: CheckedContinuation<URL, Error>
    }

    /// Guards the pending downloads, which the cancellation handler reaches from any thread.
    private final class Store: @unchecked Sendable {
        private let lock = NSLock()
        private var pending: [ModelID: Pending] = [:]

        /// Registers `entry` unless its task is already cancelled; false means "resume it now".
        func insert(_ entry: Pending, for id: ModelID) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !Task.isCancelled else { return false }
            pending[id] = entry
            return true
        }

        func remove(_ id: ModelID) -> Pending? {
            lock.lock()
            defer { lock.unlock() }
            return pending.removeValue(forKey: id)
        }

        func entry(for id: ModelID) -> Pending? {
            lock.lock()
            defer { lock.unlock() }
            return pending[id]
        }
    }

    private let store = Store()

    /// What a cancelled download throws. WhisperKit's Hugging Face client reports a cancel as
    /// `URLError(.cancelled)`; `CancellationError` is the Swift convention.
    var cancellationError: any Error = CancellationError()
    private(set) var downloadRequests: [ModelID] = []
    private(set) var tokenizerRequests: [ModelID] = []

    func download(
        variant: ModelID,
        downloadBase: URL,
        progress: @escaping @Sendable (ProgressSnapshot) -> Void
    ) async throws -> URL {
        downloadRequests.append(variant)
        let store = self.store
        let cancellationError = self.cancellationError
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                let entry = Pending(downloadBase: downloadBase, progress: progress, continuation: continuation)
                if !store.insert(entry, for: variant) {
                    continuation.resume(throwing: cancellationError)
                }
            }
        } onCancel: {
            store.remove(variant)?.continuation.resume(throwing: cancellationError)
        }
    }

    func prefetchTokenizer(for variant: ModelID, downloadBase: URL) async throws {
        tokenizerRequests.append(variant)
    }

    func isPending(_ id: ModelID) -> Bool {
        store.entry(for: id) != nil
    }

    /// Reports progress the way WhisperKit does (per file, as a fraction).
    func reportProgress(_ fraction: Double, for id: ModelID) {
        guard let entry = store.entry(for: id) else { return }
        entry.progress(ProgressSnapshot(fraction: fraction, completedFiles: Int64(fraction * 4), totalFiles: 4))
    }

    /// Completes the download, optionally writing a complete model first.
    func finish(_ id: ModelID, writingModel: Bool = true) throws {
        guard let entry = store.remove(id) else { return }
        let folder = ModelStorage.folder(downloadBase: entry.downloadBase, variant: id)
        if writingModel {
            try ModelFixtures.install(id, under: entry.downloadBase)
        }
        entry.continuation.resume(returning: folder)
    }

    func fail(_ id: ModelID, with error: any Error) {
        store.remove(id)?.continuation.resume(throwing: error)
    }
}

/// A transcription engine with scripted results. `loadGate` / `transcribeGate` hold the call
/// until the test opens them.
@MainActor
final class FakeTranscriptionEngine: TranscriptionEngine {
    var result = TranscriptionResult(
        text: "hello world", detectedLanguageCode: nil, segments: [], processingTime: 0.3, isLikelySilence: false
    )
    var transcribeError: (any Error)?
    var loadError: (any Error)?
    var loadGate: AsyncGate?
    var transcribeGate: AsyncGate?

    private(set) var loadRequests: [ModelID] = []
    private(set) var transcriptions: [(audio: AudioBuffer16k, options: TranscriptionOptions)] = []
    private(set) var unloadCount = 0
    private var current: ModelID?

    var loadedModelID: ModelID? {
        get async { current }
    }

    func load(model: ModelDescriptor, folder: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        loadRequests.append(model.id)
        progress(0.5)
        if let loadGate { await loadGate.wait() }
        if let loadError { throw loadError }
        current = model.id
        progress(1)
    }

    func unload() async {
        unloadCount += 1
        current = nil
    }

    func transcribe(_ audio: AudioBuffer16k, options: TranscriptionOptions) async throws -> TranscriptionResult {
        transcriptions.append((audio, options))
        if let transcribeGate { await transcribeGate.wait() }
        if let transcribeError { throw transcribeError }
        return result
    }
}

/// A microphone that hands back a prepared recording.
@MainActor
final class FakeAudioCapture: AudioCapturing {
    var recording = AudioFixtures.speech(seconds: 1)
    var startError: (any Error)?

    private(set) var startRequests: [String?] = []
    private(set) var stopCount = 0
    private(set) var cancelCount = 0
    private(set) var isCapturing = false

    func start(inputDeviceID: String?) throws {
        startRequests.append(inputDeviceID)
        if let startError { throw startError }
        isCapturing = true
    }

    func stop() -> AudioBuffer16k {
        stopCount += 1
        isCapturing = false
        return recording
    }

    func cancel() {
        cancelCount += 1
        isCapturing = false
    }
}

/// Records insertions instead of typing into the frontmost app.
@MainActor
final class FakeTextInserter: TextInserting {
    struct Insertion: Equatable {
        let text: String
        let context: FocusContext
        let method: InsertionMethod
        let restoreClipboard: Bool
    }

    /// The caret at the start of an empty TextEdit document, so smart capitalization applies.
    var focusContext = FocusContext(
        appBundleID: "com.apple.TextEdit", appName: "TextEdit", appPID: 4242, textBeforeCursor: "", isFieldEmpty: true
    )
    var outcome: InsertionOutcome = .inserted(.paste)
    var gate: AsyncGate?
    /// Called as an insertion begins, before `gate`.
    var onInsert: (() -> Void)?

    private(set) var captureCount = 0
    private(set) var insertions: [Insertion] = []

    func captureFocusContext() -> FocusContext {
        captureCount += 1
        return focusContext
    }

    func insert(_ text: String, context: FocusContext, method: InsertionMethod, restoreClipboard: Bool) async -> InsertionOutcome {
        insertions.append(Insertion(text: text, context: context, method: method, restoreClipboard: restoreClipboard))
        onInsert?()
        if let gate { await gate.wait() }
        return outcome
    }
}

/// Scripted permission answers for `PermissionsManager`, so nothing is read from or prompted by
/// the system.
final class PermissionScript: @unchecked Sendable {
    var microphone: PermissionStatus = .granted
    var accessibilityTrusted = false
    /// What the user answers when the microphone prompt would appear.
    var answersMicrophonePrompt = true
    private(set) var microphonePrompts = 0

    @MainActor
    func makeManager() -> PermissionsManager {
        PermissionsManager(
            microphoneStatus: { self.microphone },
            isAccessibilityTrusted: { self.accessibilityTrusted },
            requestMicrophoneAccess: {
                self.microphonePrompts += 1
                self.microphone = self.answersMicrophonePrompt ? .granted : .denied
                return self.answersMicrophonePrompt
            }
        )
    }
}

struct FakeError: LocalizedError, Equatable {
    var message = "Something broke"
    var errorDescription: String? { message }
}

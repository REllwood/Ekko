import Foundation

enum ModelInstallState: Equatable, Sendable {
    case notInstalled
    case downloading(fraction: Double, receivedBytes: Int64, totalBytes: Int64)
    case installed
    case failed(String)

    var isInstalled: Bool { self == .installed }
    var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }
}

/// Downloads, verifies, deletes, and enumerates models on disk; tracks the active model.
@Observable
@MainActor
final class ModelManager {
    private(set) var states: [ModelID: ModelInstallState] = [:]
    /// Bytes used by all installed models.
    private(set) var totalInstalledBytes: Int64 = 0

    @ObservationIgnored let settings: SettingsStore
    /// Root passed to WhisperKit as `downloadBase`: ~/Library/Application Support/Ekko/Models
    @ObservationIgnored let downloadBase: URL

    /// One in-flight download per model id.
    @ObservationIgnored private var downloadTasks: [ModelID: Task<Void, Never>] = [:]

    init(settings: SettingsStore) {
        self.settings = settings
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.downloadBase = support.appendingPathComponent("Ekko/Models", isDirectory: true)
        for model in ModelCatalog.all {
            states[model.id] = .notInstalled
        }
        refresh()
    }

    /// The model selected in settings, if it is installed.
    var activeModel: ModelDescriptor? {
        guard let id = settings.activeModelID, state(for: id).isInstalled else { return nil }
        return ModelCatalog.descriptor(for: id)
    }

    var installedModels: [ModelDescriptor] {
        ModelCatalog.all.filter { state(for: $0.id).isInstalled }
    }

    func state(for id: ModelID) -> ModelInstallState {
        states[id] ?? .notInstalled
    }

    /// Re-scans the models directory. Cheap enough for launch and for every visit to the Models page.
    func refresh() {
        var total: Int64 = 0
        for model in ModelCatalog.all {
            let folder = ModelStorage.folder(downloadBase: downloadBase, variant: model.id)
            if ModelStorage.isValidInstall(folder: folder) {
                states[model.id] = .installed
                total += ModelStorage.directorySize(of: folder)
            } else if state(for: model.id).isInstalled {
                // It was installed and the files have gone.
                states[model.id] = .notInstalled
            }
        }
        totalInstalledBytes = total

        if let active = settings.activeModelID, !state(for: active).isInstalled {
            Log.models.info("Active model \(active, privacy: .public) is not installed; clearing the selection")
            settings.activeModelID = nil
        }
    }

    /// Folder to hand to the engine, or nil if not installed.
    func folderURL(for id: ModelID) -> URL? {
        let folder = ModelStorage.folder(downloadBase: downloadBase, variant: id)
        return ModelStorage.isValidInstall(folder: folder) ? folder : nil
    }

    func download(_ id: ModelID) {
        guard let descriptor = ModelCatalog.descriptor(for: id) else {
            Log.models.error("Refusing to download unknown model \(id, privacy: .public)")
            return
        }
        guard downloadTasks[id] == nil, !state(for: id).isInstalled else { return }

        states[id] = .downloading(fraction: 0, receivedBytes: 0, totalBytes: descriptor.sizeBytes)
        Log.models.info("Downloading \(id, privacy: .public)")

        let base = downloadBase
        let throttle = ProgressThrottle()
        let onProgress: @Sendable (ProgressSnapshot) -> Void = { [weak self] snapshot in
            guard throttle.shouldEmit(snapshot) else { return }
            Task { @MainActor in
                self?.applyProgress(snapshot, to: id)
            }
        }

        downloadTasks[id] = Task { [weak self] in
            do {
                let folder = try await WhisperKitDownloader.download(
                    variant: id,
                    downloadBase: base,
                    progress: onProgress
                )
                try Task.checkCancellation()
                self?.finishDownload(of: id, at: folder)
            } catch is CancellationError {
                self?.cleanUpCancelledDownload(of: id)
            } catch {
                self?.failDownload(of: id, error: error)
            }
        }
    }

    func cancelDownload(_ id: ModelID) {
        guard let task = downloadTasks.removeValue(forKey: id) else { return }
        task.cancel()
        removeFolder(for: id)
        states[id] = .notInstalled
        Log.models.info("Cancelled the download of \(id, privacy: .public)")
    }

    func delete(_ id: ModelID) throws {
        if downloadTasks[id] != nil {
            cancelDownload(id)
            return
        }
        let folder = ModelStorage.folder(downloadBase: downloadBase, variant: id)
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
        states[id] = .notInstalled
        if settings.activeModelID == id {
            settings.activeModelID = nil
        }
        refresh()
        Log.models.info("Deleted \(id, privacy: .public)")
    }

    /// Makes `id` the active model (must be installed).
    func setActive(_ id: ModelID) {
        guard state(for: id).isInstalled else { return }
        settings.activeModelID = id
    }

    // MARK: - Download plumbing

    private func applyProgress(_ progress: ProgressSnapshot, to id: ModelID) {
        guard state(for: id).isDownloading else { return }
        // WhisperKit counts files, not bytes, so byte figures come from the catalog's size.
        let total = ModelCatalog.descriptor(for: id)?.sizeBytes ?? 0
        let fraction = min(max(progress.fraction, 0), 1)
        states[id] = .downloading(
            fraction: fraction,
            receivedBytes: Int64(fraction * Double(total)),
            totalBytes: total
        )
    }

    private func finishDownload(of id: ModelID, at folder: URL) {
        downloadTasks[id] = nil
        guard ModelStorage.isValidInstall(folder: folder) else {
            failDownload(of: id, message: "The downloaded files were incomplete. Please try again.")
            return
        }
        states[id] = .installed
        refresh()
        if settings.activeModelID == nil {
            settings.activeModelID = id
        }
        Log.models.info("Installed \(id, privacy: .public)")

        let base = downloadBase
        Task.detached(priority: .utility) {
            do {
                try await WhisperKitDownloader.prefetchTokenizer(for: id, downloadBase: base)
            } catch {
                Log.models.debug("Tokenizer prefetch for \(id, privacy: .public) skipped: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func failDownload(of id: ModelID, error: Error) {
        downloadTasks[id] = nil
        failDownload(of: id, message: error.localizedDescription)
    }

    private func failDownload(of id: ModelID, message: String) {
        downloadTasks[id] = nil
        removeFolder(for: id)
        states[id] = .failed(message)
        Log.models.error("Download of \(id, privacy: .public) failed: \(message, privacy: .public)")
    }

    private func cleanUpCancelledDownload(of id: ModelID) {
        downloadTasks[id] = nil
        removeFolder(for: id)
        if !state(for: id).isInstalled {
            states[id] = .notInstalled
        }
    }

    private func removeFolder(for id: ModelID) {
        let folder = ModelStorage.folder(downloadBase: downloadBase, variant: id)
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        do {
            try FileManager.default.removeItem(at: folder)
        } catch {
            Log.models.error("Could not remove \(folder.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Rate-limits WhisperKit's progress callback (which fires per file) to ~10 updates per second.
private final class ProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var lastEmit: TimeInterval = 0

    /// True when enough time has passed, or when the download has just finished.
    func shouldEmit(_ snapshot: ProgressSnapshot) -> Bool {
        let now = Date.timeIntervalSinceReferenceDate
        lock.lock()
        defer { lock.unlock() }
        guard snapshot.fraction >= 1 || now - lastEmit >= 0.1 else { return false }
        lastEmit = now
        return true
    }
}

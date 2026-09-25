import XCTest
@testable import Ekko

/// `ModelManager` against a temporary download root and a fake downloader: no network, and
/// nothing under Application Support.
@MainActor
final class ModelManagerTests: XCTestCase {
    private let base = "openai_whisper-base"
    private let tiny = "openai_whisper-tiny"

    private struct Harness {
        let settings: SettingsStore
        let downloader: FakeModelDownloader
        let root: URL
        let manager: ModelManager

        func folder(_ id: ModelID) -> URL {
            ModelStorage.folder(downloadBase: root, variant: id)
        }

        func folderExists(_ id: ModelID) -> Bool {
            FileManager.default.fileExists(atPath: folder(id).path)
        }
    }

    /// `preinstalled` models are written to disk before the manager first scans it.
    private func makeHarness(preinstalled: [ModelID] = [], activeModelID: ModelID? = nil) throws -> Harness {
        let defaults = TemporaryDefaults()
        let directory = try TemporaryDirectory("EkkoModelManagerTests")
        addTeardownBlock {
            defaults.remove()
            directory.remove()
        }
        for id in preinstalled {
            try ModelFixtures.install(id, under: directory.url)
        }
        let settings = SettingsStore(defaults: defaults.defaults)
        settings.activeModelID = activeModelID
        let downloader = FakeModelDownloader()
        let manager = ModelManager(settings: settings, downloadBase: directory.url, downloader: downloader)
        return Harness(settings: settings, downloader: downloader, root: directory.url, manager: manager)
    }

    private func descriptor(_ id: ModelID) -> ModelDescriptor {
        ModelCatalog.descriptor(for: id)!
    }

    // MARK: - Scanning the disk

    func testEmptyDiskHasNothingInstalled() throws {
        let h = try makeHarness()
        for model in ModelCatalog.all {
            XCTAssertEqual(h.manager.state(for: model.id), .notInstalled, model.id)
        }
        XCTAssertTrue(h.manager.installedModels.isEmpty)
        XCTAssertNil(h.manager.activeModel)
        XCTAssertEqual(h.manager.totalInstalledBytes, 0)
        XCTAssertEqual(h.manager.downloadBase, h.root)
    }

    func testModelsAlreadyOnDiskAreFoundAtLaunch() throws {
        let h = try makeHarness(preinstalled: [base, tiny], activeModelID: base)
        XCTAssertEqual(h.manager.state(for: base), .installed)
        XCTAssertEqual(h.manager.state(for: tiny), .installed)
        XCTAssertEqual(h.manager.installedModels.map(\.id), [tiny, base], "catalog order")
        XCTAssertEqual(h.manager.activeModel?.id, base)
        XCTAssertEqual(h.manager.folderURL(for: base), h.folder(base))
        XCTAssertGreaterThan(h.manager.totalInstalledBytes, 0)
    }

    func testRefreshNoticesModelsAddedAndRemovedOnDisk() throws {
        let h = try makeHarness()
        try ModelFixtures.install(tiny, under: h.root)
        h.manager.refresh()
        XCTAssertEqual(h.manager.state(for: tiny), .installed)
        let bytes = h.manager.totalInstalledBytes
        XCTAssertGreaterThan(bytes, 0)

        try FileManager.default.removeItem(at: h.folder(tiny))
        h.manager.refresh()
        XCTAssertEqual(h.manager.state(for: tiny), .notInstalled)
        XCTAssertNil(h.manager.folderURL(for: tiny))
        XCTAssertEqual(h.manager.totalInstalledBytes, 0)
    }

    func testIncompleteFolderIsNotInstalled() throws {
        let h = try makeHarness()
        try ModelFixtures.install(base, under: h.root, entries: ["AudioEncoder.mlmodelc", "config.json"])
        h.manager.refresh()
        XCTAssertEqual(h.manager.state(for: base), .notInstalled)
        XCTAssertNil(h.manager.folderURL(for: base))
    }

    func testAnActiveModelWhoseFilesAreGoneIsCleared() throws {
        let h = try makeHarness(activeModelID: base)
        XCTAssertNil(h.settings.activeModelID, "the selection points at nothing on disk")

        let other = try makeHarness(preinstalled: [base], activeModelID: base)
        try FileManager.default.removeItem(at: other.folder(base))
        other.manager.refresh()
        XCTAssertNil(other.settings.activeModelID)
        XCTAssertNil(other.manager.activeModel)
    }

    // MARK: - Active model

    func testSetActiveOnlyAcceptsInstalledModels() throws {
        let h = try makeHarness(preinstalled: [tiny])
        h.manager.setActive(base)
        XCTAssertNil(h.settings.activeModelID)
        h.manager.setActive(tiny)
        XCTAssertEqual(h.settings.activeModelID, tiny)
        XCTAssertEqual(h.manager.activeModel, descriptor(tiny))
    }

    // MARK: - Downloading

    func testDownloadReportsProgressAndInstalls() async throws {
        let h = try makeHarness()
        let size = descriptor(base).sizeBytes
        h.manager.download(base)
        XCTAssertEqual(h.manager.state(for: base), .downloading(fraction: 0, receivedBytes: 0, totalBytes: size))

        await waitUntil("the downloader is asked") { h.downloader.isPending(base) }
        XCTAssertEqual(h.downloader.downloadRequests, [base])

        h.downloader.reportProgress(0.25, for: base)
        await waitUntil("progress arrives") { h.manager.state(for: base) != .downloading(fraction: 0, receivedBytes: 0, totalBytes: size) }
        XCTAssertEqual(
            h.manager.state(for: base),
            .downloading(fraction: 0.25, receivedBytes: Int64(0.25 * Double(size)), totalBytes: size)
        )

        // The final report always gets through the throttle, and fractions are clamped.
        h.downloader.reportProgress(1.7, for: base)
        await waitUntil("the final progress arrives") {
            h.manager.state(for: base) == .downloading(fraction: 1, receivedBytes: size, totalBytes: size)
        }

        try h.downloader.finish(base)
        await waitUntil("the model is installed") { h.manager.state(for: base) == .installed }
        XCTAssertEqual(h.manager.installedModels.map(\.id), [base])
        XCTAssertGreaterThan(h.manager.totalInstalledBytes, 0)
        await waitUntil("the tokenizer is fetched") { h.downloader.tokenizerRequests == [base] }
    }

    func testTheFirstInstalledModelBecomesActive() async throws {
        let h = try makeHarness()
        h.manager.download(base)
        await waitUntil("the downloader is asked") { h.downloader.isPending(base) }
        try h.downloader.finish(base)
        await waitUntil("installed") { h.manager.state(for: base) == .installed }
        XCTAssertEqual(h.settings.activeModelID, base)
    }

    func testALaterDownloadLeavesTheActiveModelAlone() async throws {
        let h = try makeHarness(preinstalled: [tiny], activeModelID: tiny)
        h.manager.download(base)
        await waitUntil("the downloader is asked") { h.downloader.isPending(base) }
        try h.downloader.finish(base)
        await waitUntil("installed") { h.manager.state(for: base) == .installed }
        XCTAssertEqual(h.settings.activeModelID, tiny)
    }

    func testRedundantDownloadRequestsAreIgnored() async throws {
        let h = try makeHarness(preinstalled: [tiny])
        h.manager.download(tiny)                   // already installed
        h.manager.download("not-a-catalog-model")  // unknown
        h.manager.download(base)
        h.manager.download(base)                   // already downloading
        await waitUntil("the downloader is asked") { h.downloader.isPending(base) }
        await drainMainActor()
        XCTAssertEqual(h.downloader.downloadRequests, [base])
        XCTAssertEqual(h.manager.state(for: tiny), .installed)
        XCTAssertEqual(h.manager.state(for: "not-a-catalog-model"), .notInstalled)
    }

    func testAFailedDownloadReportsTheErrorAndCleansUp() async throws {
        let h = try makeHarness()
        h.manager.download(base)
        await waitUntil("the downloader is asked") { h.downloader.isPending(base) }
        try ModelFixtures.install(base, under: h.root, entries: ["AudioEncoder.mlmodelc"]) // partial files

        h.downloader.fail(base, with: FakeError(message: "The network connection was lost."))
        await waitUntil("the download fails") { h.manager.state(for: base) == .failed("The network connection was lost.") }
        XCTAssertFalse(h.folderExists(base), "partial files are removed")
        XCTAssertNil(h.settings.activeModelID)
        XCTAssertEqual(h.downloader.tokenizerRequests, [])

        // "Try again" starts a fresh download.
        h.manager.download(base)
        await waitUntil("the retry reaches the downloader") { h.downloader.isPending(base) }
        XCTAssertEqual(h.downloader.downloadRequests, [base, base])
    }

    func testAnIncompleteDownloadFailsInsteadOfInstalling() async throws {
        let h = try makeHarness()
        h.manager.download(base)
        await waitUntil("the downloader is asked") { h.downloader.isPending(base) }
        try ModelFixtures.install(base, under: h.root, entries: ["AudioEncoder.mlmodelc", "config.json"])
        try h.downloader.finish(base, writingModel: false)

        await waitUntil("the download fails") {
            h.manager.state(for: base) == .failed("The downloaded files were incomplete. Please try again.")
        }
        XCTAssertFalse(h.folderExists(base))
        XCTAssertNil(h.settings.activeModelID)
    }

    // MARK: - Cancelling

    func testCancelRemovesThePartialFolderAndResets() async throws {
        let h = try makeHarness()
        h.manager.download(base)
        await waitUntil("the downloader is asked") { h.downloader.isPending(base) }
        try ModelFixtures.install(base, under: h.root, entries: ["MelSpectrogram.mlmodelc"])

        h.manager.cancelDownload(base)
        XCTAssertEqual(h.manager.state(for: base), .notInstalled)
        XCTAssertFalse(h.folderExists(base))
        XCTAssertFalse(h.downloader.isPending(base), "the download task was cancelled")

        await drainMainActor()
        XCTAssertEqual(h.manager.state(for: base), .notInstalled)
        XCTAssertNil(h.settings.activeModelID)
    }

    func testCancelReportedAsURLErrorIsNotAFailure() async throws {
        // WhisperKit's Hugging Face client ends a cancelled download with URLError(.cancelled).
        let h = try makeHarness()
        h.downloader.cancellationError = URLError(.cancelled)
        h.manager.download(base)
        await waitUntil("the downloader is asked") { h.downloader.isPending(base) }

        h.manager.cancelDownload(base)
        // The downloader wrote one more file before it noticed the cancel.
        try ModelFixtures.install(base, under: h.root, entries: ["TextDecoder.mlmodelc"])
        await waitUntil("the late files are tidied away") { !h.folderExists(base) }
        await drainMainActor()

        XCTAssertEqual(h.manager.state(for: base), .notInstalled)
    }

    func testCancelThenDownloadAgainKeepsTheNewDownload() async throws {
        let h = try makeHarness()
        h.manager.download(base)
        await waitUntil("the first download starts") { h.downloader.isPending(base) }

        h.manager.cancelDownload(base)
        h.manager.download(base) // Straight away, before the cancelled task has wound down.
        await waitUntil("the second download starts") {
            h.downloader.downloadRequests.count == 2 && h.downloader.isPending(base)
        }
        try ModelFixtures.install(base, under: h.root, entries: ["AudioEncoder.mlmodelc"]) // the new download's files
        await drainMainActor()

        XCTAssertTrue(h.manager.state(for: base).isDownloading, "\(h.manager.state(for: base))")
        XCTAssertTrue(h.folderExists(base), "the new download's files must survive the old task's cleanup")
        h.downloader.reportProgress(0.5, for: base)
        await waitUntil("progress for the new download") {
            if case .downloading(let fraction, _, _) = h.manager.state(for: base) { return fraction == 0.5 }
            return false
        }

        // The new download can still be cancelled.
        h.manager.cancelDownload(base)
        XCTAssertFalse(h.downloader.isPending(base))
        XCTAssertEqual(h.manager.state(for: base), .notInstalled)
    }

    func testCancelWithNothingDownloadingDoesNothing() throws {
        let h = try makeHarness(preinstalled: [tiny])
        h.manager.cancelDownload(tiny)
        XCTAssertEqual(h.manager.state(for: tiny), .installed)
        XCTAssertTrue(h.folderExists(tiny))
    }

    // MARK: - Deleting

    func testDeleteRemovesTheFiles() throws {
        let h = try makeHarness(preinstalled: [base, tiny], activeModelID: tiny)
        try h.manager.delete(base)
        XCTAssertEqual(h.manager.state(for: base), .notInstalled)
        XCTAssertFalse(h.folderExists(base))
        XCTAssertEqual(h.manager.installedModels.map(\.id), [tiny])
        XCTAssertEqual(h.settings.activeModelID, tiny, "deleting another model keeps the selection")
    }

    func testDeletingTheActiveModelClearsTheSelection() throws {
        let h = try makeHarness(preinstalled: [base, tiny], activeModelID: base)
        try h.manager.delete(base)
        XCTAssertNil(h.settings.activeModelID)
        XCTAssertNil(h.manager.activeModel)
        XCTAssertEqual(h.manager.state(for: tiny), .installed, "no other model is picked automatically")
    }

    func testDeletingAModelThatIsNotOnDiskIsHarmless() throws {
        let h = try makeHarness()
        XCTAssertNoThrow(try h.manager.delete(base))
        XCTAssertEqual(h.manager.state(for: base), .notInstalled)
    }

    func testDeletingADownloadInProgressCancelsIt() async throws {
        let h = try makeHarness()
        h.manager.download(base)
        await waitUntil("the downloader is asked") { h.downloader.isPending(base) }
        try h.manager.delete(base)
        XCTAssertFalse(h.downloader.isPending(base))
        XCTAssertEqual(h.manager.state(for: base), .notInstalled)
    }

    // MARK: - Install state

    func testInstallStateHelpers() {
        XCTAssertTrue(ModelInstallState.installed.isInstalled)
        XCTAssertFalse(ModelInstallState.installed.isDownloading)
        let downloading = ModelInstallState.downloading(fraction: 0.5, receivedBytes: 5, totalBytes: 10)
        XCTAssertTrue(downloading.isDownloading)
        XCTAssertFalse(downloading.isInstalled)
        XCTAssertFalse(ModelInstallState.failed("x").isInstalled)
        XCTAssertFalse(ModelInstallState.notInstalled.isDownloading)
    }
}

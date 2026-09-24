import XCTest
@testable import Ekko

/// Covers the pure part of `ModelManager`: where a variant lives on disk and whether the files
/// found there add up to a loadable model.
final class ModelStorageTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("EkkoModelStorageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root, FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
    }

    // MARK: - Layout

    func testVariantFolderMatchesWhisperKitsHubLayout() {
        let base = URL(fileURLWithPath: "/tmp/Ekko/Models", isDirectory: true)
        let folder = ModelStorage.folder(downloadBase: base, variant: "openai_whisper-base")
        XCTAssertEqual(
            folder.path,
            "/tmp/Ekko/Models/models/argmaxinc/whisperkit-coreml/openai_whisper-base"
        )
        XCTAssertEqual(
            ModelStorage.variantsRoot(downloadBase: base).path,
            "/tmp/Ekko/Models/models/argmaxinc/whisperkit-coreml"
        )
    }

    func testDefaultDownloadBaseIsInApplicationSupport() {
        let base = ModelStorage.defaultDownloadBase
        XCTAssertTrue(base.path.hasSuffix("Application Support/Ekko/Models"), base.path)
    }

    // MARK: - Install validation

    func testCompleteFolderIsValid() throws {
        let folder = try makeVariantFolder(entries: ModelStorage.requiredEntries)
        XCTAssertTrue(ModelStorage.isValidInstall(folder: folder))
    }

    func testFolderMissingAnyRequiredEntryIsInvalid() throws {
        for missing in ModelStorage.requiredEntries {
            let entries = ModelStorage.requiredEntries.filter { $0 != missing }
            let folder = try makeVariantFolder(name: "without-\(missing)", entries: entries)
            XCTAssertFalse(
                ModelStorage.isValidInstall(folder: folder),
                "A folder without \(missing) must not count as installed"
            )
        }
    }

    func testEmptyFolderIsInvalid() throws {
        let folder = try makeVariantFolder(entries: [])
        XCTAssertFalse(ModelStorage.isValidInstall(folder: folder))
    }

    func testMissingFolderIsInvalid() {
        XCTAssertFalse(ModelStorage.isValidInstall(folder: root.appendingPathComponent("nope", isDirectory: true)))
    }

    func testFileWhereAFolderShouldBeIsInvalid() throws {
        let file = root.appendingPathComponent("openai_whisper-base")
        try Data("not a model".utf8).write(to: file)
        XCTAssertFalse(ModelStorage.isValidInstall(folder: file))
    }

    func testPartialDownloadIsInvalidUntilEveryFileArrives() throws {
        let folder = try makeVariantFolder(entries: ["MelSpectrogram.mlmodelc"])
        XCTAssertFalse(ModelStorage.isValidInstall(folder: folder))

        try makeEntry("AudioEncoder.mlmodelc", in: folder)
        try makeEntry("TextDecoder.mlmodelc", in: folder)
        XCTAssertFalse(ModelStorage.isValidInstall(folder: folder))

        try makeEntry("config.json", in: folder)
        XCTAssertTrue(ModelStorage.isValidInstall(folder: folder))
    }

    // MARK: - Size

    func testDirectorySizeCountsFiles() throws {
        let folder = try makeVariantFolder(entries: ModelStorage.requiredEntries)
        XCTAssertGreaterThan(ModelStorage.directorySize(of: folder), 0)
        XCTAssertEqual(ModelStorage.directorySize(of: root.appendingPathComponent("absent")), 0)
    }

    // MARK: - Helpers

    private func makeVariantFolder(name: String = "openai_whisper-base", entries: [String]) throws -> URL {
        let folder = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for entry in entries {
            try makeEntry(entry, in: folder)
        }
        return folder
    }

    /// `.mlmodelc` entries are directories on disk; `config.json` is a plain file.
    private func makeEntry(_ name: String, in folder: URL) throws {
        let url = folder.appendingPathComponent(name)
        if name.hasSuffix(".mlmodelc") {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try Data(repeating: 0, count: 1024).write(to: url.appendingPathComponent("coremldata.bin"))
        } else {
            try Data("{\"model_type\":\"whisper\"}".utf8).write(to: url)
        }
    }
}

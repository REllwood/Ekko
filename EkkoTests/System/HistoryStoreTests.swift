import XCTest
@testable import Ekko

final class HistoryStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("EkkoHistoryTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func entry(_ text: String, index: Int = 0) -> TranscriptEntry {
        TranscriptEntry(
            text: text,
            date: Date(timeIntervalSinceReferenceDate: TimeInterval(index)),
            audioDuration: 1.5,
            processingTime: 0.4,
            languageCode: "en",
            modelID: "openai_whisper-base",
            targetAppName: "TextEdit",
            targetAppBundleID: "com.apple.TextEdit"
        )
    }

    func testLoadingWithoutAFileReturnsEmpty() {
        let store = HistoryStore(directory: directory)
        XCTAssertTrue(store.load().isEmpty)
    }

    func testSaveAndLoadRoundTrip() {
        let store = HistoryStore(directory: directory)
        let entries = [entry("one", index: 0), entry("two", index: 1)]
        store.save(entries)

        let loaded = HistoryStore(directory: directory).load()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded.map(\.text), ["one", "two"])
        XCTAssertEqual(loaded.first?.id, entries.first?.id)
        XCTAssertEqual(loaded.first?.languageCode, "en")
        XCTAssertEqual(loaded.last?.modelID, "openai_whisper-base")
        XCTAssertEqual(
            loaded.first?.date.timeIntervalSinceReferenceDate ?? -1,
            entries.first?.date.timeIntervalSinceReferenceDate ?? -2,
            accuracy: 1.0
        )
    }

    func testSaveKeepsOnlyTheNewestEntries() {
        let store = HistoryStore(directory: directory)
        let entries = (0..<(HistoryStore.maxEntries + 25)).map { entry("entry \($0)", index: $0) }
        store.save(entries)

        let loaded = store.load()
        XCTAssertEqual(loaded.count, HistoryStore.maxEntries)
        XCTAssertEqual(loaded.first?.text, "entry 25")
        XCTAssertEqual(loaded.last?.text, "entry \(HistoryStore.maxEntries + 24)")
    }

    func testTrimmedIsANoOpBelowTheCap() {
        let entries = [entry("a"), entry("b")]
        XCTAssertEqual(HistoryStore.trimmed(entries).count, 2)
    }

    func testClearRemovesTheFile() {
        let store = HistoryStore(directory: directory)
        store.save([entry("one")])
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL.path))
        store.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
        XCTAssertTrue(store.load().isEmpty)
    }

    func testCorruptFileIsIgnored() throws {
        let store = HistoryStore(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.fileURL)
        XCTAssertTrue(store.load().isEmpty)
    }

    func testDefaultLocationIsInsideApplicationSupport() {
        let store = HistoryStore()
        XCTAssertEqual(store.fileURL.lastPathComponent, "history.json")
        XCTAssertTrue(store.fileURL.deletingLastPathComponent().lastPathComponent == "Ekko")
    }
}

import Foundation

/// JSON persistence for the dictation history.
/// File: ~/Library/Application Support/Ekko/history.json (overridable for tests).
/// Never call from the main actor on a hot path — the controller saves from a detached task.
final class HistoryStore: Sendable {
    /// Hard cap; older entries are dropped.
    static let maxEntries = 200

    let fileURL: URL

    init(directory: URL? = nil, fileName: String = "history.json") {
        let base: URL
        if let directory {
            base = directory
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            base = support.appendingPathComponent("Ekko", isDirectory: true)
        }
        self.fileURL = base.appendingPathComponent(fileName)
    }

    func load() -> [TranscriptEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let entries = try? decoder.decode([TranscriptEntry].self, from: data) else {
            Log.dictation.error("History file could not be decoded; starting empty")
            return []
        }
        return Self.trimmed(entries)
    }

    /// Writes the newest `maxEntries` entries atomically.
    func save(_ entries: [TranscriptEntry]) {
        let trimmed = Self.trimmed(entries)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.withoutEscapingSlashes]
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(trimmed)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Log.dictation.error("Could not write history: \(error.localizedDescription, privacy: .public)")
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    static func trimmed(_ entries: [TranscriptEntry]) -> [TranscriptEntry] {
        guard entries.count > maxEntries else { return entries }
        return Array(entries.suffix(maxEntries))
    }
}

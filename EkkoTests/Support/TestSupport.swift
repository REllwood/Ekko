import AppKit
import XCTest
@testable import Ekko

/// A one-shot latch for async fakes: `wait()` suspends until `open()` is called, and returns at
/// once after that. Lets a test hold the pipeline at a precise step and look at the state there.
final class AsyncGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if isOpen {
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    func open() {
        lock.lock()
        isOpen = true
        let waiting = waiters
        waiters = []
        lock.unlock()
        waiting.forEach { $0.resume() }
    }
}

/// A test-only `UserDefaults` suite, so nothing reads or writes the real preferences.
final class TemporaryDefaults {
    /// One suite name for every test, wiped when a test starts and ends. cfprefsd writes an empty
    /// plist for each suite it has seen, even after `removePersistentDomain` (and sometimes after
    /// the file is deleted), so a fresh name per test would leave a file per test in
    /// ~/Library/Preferences.
    let suiteName = "com.rhysellwood.ekko.unit-tests"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    func remove() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

/// A fresh folder under the temporary directory (never Application Support).
final class TemporaryDirectory {
    let url: URL

    init(_ name: String = "EkkoTests") throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

/// A private, uniquely named pasteboard, so tests never touch the user's clipboard.
final class TemporaryPasteboard {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.rhysellwood.ekko.tests.\(UUID().uuidString)"))

    func remove() {
        pasteboard.releaseGlobally()
    }
}

enum ModelFixtures {
    /// Writes the entries `ModelStorage.isValidInstall` requires for `id` under `downloadBase`,
    /// laid out the way WhisperKit's hub client stores them. Returns the variant folder.
    @discardableResult
    static func install(_ id: ModelID, under downloadBase: URL, entries: [String] = ModelStorage.requiredEntries) throws -> URL {
        let folder = ModelStorage.folder(downloadBase: downloadBase, variant: id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for entry in entries {
            let url = folder.appendingPathComponent(entry)
            if entry.hasSuffix(".mlmodelc") {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                try Data(repeating: 0, count: 4096).write(to: url.appendingPathComponent("coremldata.bin"))
            } else {
                try Data("{\"model_type\":\"whisper\"}".utf8).write(to: url)
            }
        }
        return folder
    }
}

/// Recordings for `AudioBuffer16k`, sized against the controller's "nothing heard" guards.
enum AudioFixtures {
    /// A steady tone well above every loudness threshold.
    static func speech(seconds: Double, amplitude: Float = 0.2) -> AudioBuffer16k {
        let count = Int(seconds * AudioBuffer16k.sampleRate)
        return AudioBuffer16k(samples: (0..<count).map { Float(sin(Double($0) * 0.1)) * amplitude })
    }

    static func silence(seconds: Double) -> AudioBuffer16k {
        AudioBuffer16k(samples: [Float](repeating: 0, count: Int(seconds * AudioBuffer16k.sampleRate)))
    }
}

extension XCTestCase {
    /// Polls `condition` on the main actor until it holds. Fails (rather than hangs) after
    /// `timeout`; the timeout only bounds a broken test, it is never what a passing test waits on.
    @MainActor
    func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Timed out waiting until \(description)", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    /// Lets every job already queued on the main actor run first (the main queue is FIFO).
    @MainActor
    func drainMainActor() async {
        for _ in 0..<5 { await Task.yield() }
    }
}

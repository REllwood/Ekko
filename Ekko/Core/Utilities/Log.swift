import Foundation
import os

/// Unified logging. Use `Log.<category>.info/debug/error`. Never log transcribed text at
/// `.info` or above — user speech is private; use `.debug` with `privacy: .private` if needed.
enum Log {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.rhysellwood.ekko"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let models = Logger(subsystem: subsystem, category: "models")
    static let dictation = Logger(subsystem: subsystem, category: "dictation")
    static let input = Logger(subsystem: subsystem, category: "input")
    static let permissions = Logger(subsystem: subsystem, category: "permissions")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}

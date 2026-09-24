import AppKit

/// Short, quiet cues for the start/stop/failure of a dictation. Uses the stock macOS sounds so
/// nothing has to ship in the bundle. Honours `SettingsStore.playSounds`.
@MainActor
final class SoundPlayer {
    enum Cue: String, CaseIterable, Sendable {
        case start
        case stop
        case error

        /// Stock sound in /System/Library/Sounds.
        var systemSoundName: String {
            switch self {
            case .start: return "Tink"
            case .stop: return "Pop"
            case .error: return "Basso"
            }
        }

        var volume: Float {
            switch self {
            case .start: return 0.25
            case .stop: return 0.22
            case .error: return 0.35
            }
        }
    }

    /// Master switch, mirrored from settings by the caller.
    var isEnabled = true

    private var cache: [Cue: NSSound] = [:]

    init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }

    func play(_ cue: Cue) {
        guard isEnabled else { return }
        guard let sound = sound(for: cue) else { return }
        if sound.isPlaying { sound.stop() }
        sound.volume = cue.volume
        sound.play()
    }

    private func sound(for cue: Cue) -> NSSound? {
        if let cached = cache[cue] { return cached }
        let path = "/System/Library/Sounds/\(cue.systemSoundName).aiff"
        guard FileManager.default.fileExists(atPath: path),
              let sound = NSSound(contentsOfFile: path, byReference: true) else {
            Log.app.debug("System sound missing: \(path, privacy: .public)")
            return nil
        }
        cache[cue] = sound
        return sound
    }
}

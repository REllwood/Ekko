import Foundation

/// Dependency container. All long-lived services live here so UI and system layers share one
/// instance of each. Everything is main-actor isolated except the transcription engine, which
/// does its work off the main thread internally.
@MainActor
final class AppContainer {
    static let shared = AppContainer()

    let settings: SettingsStore
    let hardware: HardwareProfile
    let permissions: PermissionsManager
    let modelManager: ModelManager
    let audio: AudioCaptureService
    let engine: any TranscriptionEngine
    let hotkeys: HotkeyManager
    let dictation: DictationController
    let focusTracker: FocusTracker

    private init() {
        settings = SettingsStore()
        hardware = HardwareProfile.detect()
        permissions = PermissionsManager()
        modelManager = ModelManager(settings: settings)
        audio = AudioCaptureService()
        engine = WhisperKitEngine()
        hotkeys = HotkeyManager()
        dictation = DictationController(
            settings: settings,
            permissions: permissions,
            modelManager: modelManager,
            audio: audio,
            engine: engine,
            hotkeys: hotkeys
        )
        focusTracker = FocusTracker()
    }
}

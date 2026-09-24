import Foundation

/// All user preferences, persisted to UserDefaults. Fixed contract — add keys via `Keys`.
/// Observers (hotkey manager, launch-at-login, etc.) watch these with `withObservationTracking`.
@Observable
@MainActor
final class SettingsStore {
    @ObservationIgnored private let defaults: UserDefaults

    enum Keys {
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let activeModelID = "activeModelID"
        static let languageCode = "languageCode"
        static let hotkey = "hotkey"
        static let activationMode = "activationMode"
        static let insertionMethod = "insertionMethod"
        static let restoreClipboardAfterPaste = "restoreClipboardAfterPaste"
        static let smartCapitalization = "smartCapitalization"
        static let smartSpacing = "smartSpacing"
        static let voiceCommandsEnabled = "voiceCommandsEnabled"
        static let showHUD = "showHUD"
        static let playSounds = "playSounds"
        static let launchAtLogin = "launchAtLogin"
        static let inputDeviceID = "inputDeviceID"
        static let keepHistory = "keepHistory"
        static let hasSeenModelRecommendation = "hasSeenModelRecommendation"
        static let showFieldMic = "showFieldMic"
        static let dismissedUpgradeModelID = "dismissedUpgradeModelID"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        activeModelID = defaults.string(forKey: Keys.activeModelID)
        languageCode = defaults.string(forKey: Keys.languageCode)
        hotkey = Self.decode(Hotkey.self, from: defaults, key: Keys.hotkey) ?? .default
        activationMode = ActivationMode(rawValue: defaults.string(forKey: Keys.activationMode) ?? "") ?? .auto
        insertionMethod = InsertionMethod(rawValue: defaults.string(forKey: Keys.insertionMethod) ?? "") ?? .auto
        restoreClipboardAfterPaste = defaults.object(forKey: Keys.restoreClipboardAfterPaste) as? Bool ?? true
        smartCapitalization = defaults.object(forKey: Keys.smartCapitalization) as? Bool ?? true
        smartSpacing = defaults.object(forKey: Keys.smartSpacing) as? Bool ?? true
        voiceCommandsEnabled = defaults.object(forKey: Keys.voiceCommandsEnabled) as? Bool ?? false
        showHUD = defaults.object(forKey: Keys.showHUD) as? Bool ?? true
        playSounds = defaults.object(forKey: Keys.playSounds) as? Bool ?? true
        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        inputDeviceID = defaults.string(forKey: Keys.inputDeviceID)
        keepHistory = defaults.object(forKey: Keys.keepHistory) as? Bool ?? true
        hasSeenModelRecommendation = defaults.bool(forKey: Keys.hasSeenModelRecommendation)
        showFieldMic = defaults.object(forKey: Keys.showFieldMic) as? Bool ?? true
        dismissedUpgradeModelID = defaults.string(forKey: Keys.dismissedUpgradeModelID)
    }

    // MARK: - Onboarding

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    var hasSeenModelRecommendation: Bool {
        didSet { defaults.set(hasSeenModelRecommendation, forKey: Keys.hasSeenModelRecommendation) }
    }

    // MARK: - Model & language

    /// Catalog id of the model to use. nil until the user has installed one.
    var activeModelID: ModelID? {
        didSet { defaults.set(activeModelID, forKey: Keys.activeModelID) }
    }

    /// Whisper language code, or nil for automatic detection.
    var languageCode: String? {
        didSet { defaults.set(languageCode, forKey: Keys.languageCode) }
    }

    var isEnglish: Bool { languageCode == "en" }

    // MARK: - Trigger

    var hotkey: Hotkey {
        didSet { Self.encode(hotkey, to: defaults, key: Keys.hotkey) }
    }

    var activationMode: ActivationMode {
        didSet { defaults.set(activationMode.rawValue, forKey: Keys.activationMode) }
    }

    // MARK: - Insertion & formatting

    var insertionMethod: InsertionMethod {
        didSet { defaults.set(insertionMethod.rawValue, forKey: Keys.insertionMethod) }
    }

    var restoreClipboardAfterPaste: Bool {
        didSet { defaults.set(restoreClipboardAfterPaste, forKey: Keys.restoreClipboardAfterPaste) }
    }

    var smartCapitalization: Bool {
        didSet { defaults.set(smartCapitalization, forKey: Keys.smartCapitalization) }
    }

    var smartSpacing: Bool {
        didSet { defaults.set(smartSpacing, forKey: Keys.smartSpacing) }
    }

    /// "new line", "new paragraph", etc. spoken commands.
    var voiceCommandsEnabled: Bool {
        didSet { defaults.set(voiceCommandsEnabled, forKey: Keys.voiceCommandsEnabled) }
    }

    // MARK: - Feedback

    var showHUD: Bool {
        didSet { defaults.set(showHUD, forKey: Keys.showHUD) }
    }

    /// Show a small clickable mic next to whichever text field has focus, in any app.
    var showFieldMic: Bool {
        didSet { defaults.set(showFieldMic, forKey: Keys.showFieldMic) }
    }

    /// The recommended model the user said "not now" to, so the upgrade card stays hidden for it.
    var dismissedUpgradeModelID: ModelID? {
        didSet { defaults.set(dismissedUpgradeModelID, forKey: Keys.dismissedUpgradeModelID) }
    }

    var playSounds: Bool {
        didSet { defaults.set(playSounds, forKey: Keys.playSounds) }
    }

    // MARK: - System

    /// Desired state; `LaunchAtLogin` applies it with SMAppService and reports failures.
    var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }

    /// CoreAudio device UID, or nil for the system default microphone.
    var inputDeviceID: String? {
        didSet { defaults.set(inputDeviceID, forKey: Keys.inputDeviceID) }
    }

    var keepHistory: Bool {
        didSet { defaults.set(keepHistory, forKey: Keys.keepHistory) }
    }

    // MARK: - Helpers

    private static func decode<T: Decodable>(_ type: T.Type, from defaults: UserDefaults, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func encode<T: Encodable>(_ value: T, to defaults: UserDefaults, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }
}

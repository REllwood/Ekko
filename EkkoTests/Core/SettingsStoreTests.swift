import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Ekko

/// Every test gets its own `UserDefaults` suite; the real preferences are never read or written.
@MainActor
final class SettingsStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = TemporaryDefaults()
        addTeardownBlock { suite.remove() }
        return suite.defaults
    }

    // MARK: - Defaults

    func testFreshInstallDefaults() {
        let settings = SettingsStore(defaults: makeDefaults())
        XCTAssertFalse(settings.hasCompletedOnboarding)
        XCTAssertFalse(settings.hasSeenModelRecommendation)
        XCTAssertNil(settings.activeModelID)
        XCTAssertNil(settings.languageCode, "automatic language detection")
        XCTAssertFalse(settings.isEnglish)
        XCTAssertEqual(settings.hotkey, .default)
        XCTAssertEqual(settings.hotkey.kind, .modifier(.rightOption))
        XCTAssertEqual(settings.activationMode, .auto)
        XCTAssertEqual(settings.insertionMethod, .auto)
        XCTAssertTrue(settings.restoreClipboardAfterPaste)
        XCTAssertTrue(settings.smartCapitalization)
        XCTAssertTrue(settings.smartSpacing)
        XCTAssertFalse(settings.voiceCommandsEnabled)
        XCTAssertTrue(settings.showHUD)
        XCTAssertTrue(settings.showFieldMic)
        XCTAssertNil(settings.dismissedUpgradeModelID)
        XCTAssertTrue(settings.playSounds)
        XCTAssertFalse(settings.launchAtLogin)
        XCTAssertNil(settings.inputDeviceID, "the system default microphone")
        XCTAssertTrue(settings.keepHistory)
    }

    func testReadingDefaultsWritesNothing() {
        let defaults = makeDefaults()
        _ = SettingsStore(defaults: defaults)
        for key in allKeys {
            XCTAssertNil(defaults.object(forKey: key), key)
        }
    }

    // MARK: - Persistence

    func testEverySettingSurvivesARelaunch() {
        let defaults = makeDefaults()
        let combo = Hotkey(kind: .combo(keyCode: UInt16(kVK_Space), modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue))

        let first = SettingsStore(defaults: defaults)
        first.hasCompletedOnboarding = true
        first.hasSeenModelRecommendation = true
        first.activeModelID = "openai_whisper-small"
        first.languageCode = "fr"
        first.hotkey = combo
        first.activationMode = .holdToTalk
        first.insertionMethod = .accessibility
        first.restoreClipboardAfterPaste = false
        first.smartCapitalization = false
        first.smartSpacing = false
        first.voiceCommandsEnabled = true
        first.showHUD = false
        first.showFieldMic = false
        first.dismissedUpgradeModelID = "openai_whisper-large-v3-v20240930_turbo"
        first.playSounds = false
        first.launchAtLogin = true
        first.inputDeviceID = "BuiltInMicrophoneDevice"
        first.keepHistory = false

        let second = SettingsStore(defaults: defaults)
        XCTAssertTrue(second.hasCompletedOnboarding)
        XCTAssertTrue(second.hasSeenModelRecommendation)
        XCTAssertEqual(second.activeModelID, "openai_whisper-small")
        XCTAssertEqual(second.languageCode, "fr")
        XCTAssertEqual(second.hotkey, combo)
        XCTAssertEqual(second.activationMode, .holdToTalk)
        XCTAssertEqual(second.insertionMethod, .accessibility)
        XCTAssertFalse(second.restoreClipboardAfterPaste)
        XCTAssertFalse(second.smartCapitalization)
        XCTAssertFalse(second.smartSpacing)
        XCTAssertTrue(second.voiceCommandsEnabled)
        XCTAssertFalse(second.showHUD)
        XCTAssertFalse(second.showFieldMic)
        XCTAssertEqual(second.dismissedUpgradeModelID, "openai_whisper-large-v3-v20240930_turbo")
        XCTAssertFalse(second.playSounds)
        XCTAssertTrue(second.launchAtLogin)
        XCTAssertEqual(second.inputDeviceID, "BuiltInMicrophoneDevice")
        XCTAssertFalse(second.keepHistory)
    }

    func testEveryEnumCaseRoundTrips() {
        let defaults = makeDefaults()
        for mode in ActivationMode.allCases {
            SettingsStore(defaults: defaults).activationMode = mode
            XCTAssertEqual(SettingsStore(defaults: defaults).activationMode, mode)
        }
        for method in InsertionMethod.allCases {
            SettingsStore(defaults: defaults).insertionMethod = method
            XCTAssertEqual(SettingsStore(defaults: defaults).insertionMethod, method)
        }
        for key in ModifierKey.allCases {
            SettingsStore(defaults: defaults).hotkey = Hotkey(kind: .modifier(key))
            XCTAssertEqual(SettingsStore(defaults: defaults).hotkey, Hotkey(kind: .modifier(key)))
        }
    }

    func testClearingAnOptionalRemovesIt() {
        let defaults = makeDefaults()
        let first = SettingsStore(defaults: defaults)
        first.activeModelID = "openai_whisper-base"
        first.languageCode = "de"
        first.inputDeviceID = "USB"
        first.activeModelID = nil
        first.languageCode = nil
        first.inputDeviceID = nil

        XCTAssertNil(defaults.object(forKey: SettingsStore.Keys.activeModelID))
        let second = SettingsStore(defaults: defaults)
        XCTAssertNil(second.activeModelID)
        XCTAssertNil(second.languageCode)
        XCTAssertNil(second.inputDeviceID)
    }

    func testValuesAreStoredUnderTheirDocumentedKeys() throws {
        let defaults = makeDefaults()
        let settings = SettingsStore(defaults: defaults)
        settings.activationMode = .toggle
        settings.insertionMethod = .type
        settings.playSounds = false
        settings.hotkey = Hotkey(kind: .modifier(.fn))

        XCTAssertEqual(defaults.string(forKey: SettingsStore.Keys.activationMode), "toggle")
        XCTAssertEqual(defaults.string(forKey: SettingsStore.Keys.insertionMethod), "type")
        XCTAssertEqual(defaults.object(forKey: SettingsStore.Keys.playSounds) as? Bool, false)
        let data = try XCTUnwrap(defaults.data(forKey: SettingsStore.Keys.hotkey))
        XCTAssertEqual(try JSONDecoder().decode(Hotkey.self, from: data), Hotkey(kind: .modifier(.fn)))
    }

    func testIsEnglishFollowsTheLanguage() {
        let settings = SettingsStore(defaults: makeDefaults())
        settings.languageCode = "en"
        XCTAssertTrue(settings.isEnglish)
        settings.languageCode = "es"
        XCTAssertFalse(settings.isEnglish)
    }

    // MARK: - Corrupt or foreign values

    func testCorruptValuesFallBackToDefaults() {
        let defaults = makeDefaults()
        defaults.set(Data("not json".utf8), forKey: SettingsStore.Keys.hotkey)
        defaults.set("sometimes", forKey: SettingsStore.Keys.activationMode)
        defaults.set("telepathy", forKey: SettingsStore.Keys.insertionMethod)
        defaults.set("yes please", forKey: SettingsStore.Keys.restoreClipboardAfterPaste)
        defaults.set("loud", forKey: SettingsStore.Keys.playSounds)
        defaults.set(["a", "b"], forKey: SettingsStore.Keys.keepHistory)

        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.hotkey, .default)
        XCTAssertEqual(settings.activationMode, .auto)
        XCTAssertEqual(settings.insertionMethod, .auto)
        XCTAssertTrue(settings.restoreClipboardAfterPaste)
        XCTAssertTrue(settings.playSounds)
        XCTAssertTrue(settings.keepHistory)
    }

    func testAHotkeyStoredWithTheWrongTypeFallsBackToTheDefault() {
        let defaults = makeDefaults()
        defaults.set("Right Option", forKey: SettingsStore.Keys.hotkey)
        XCTAssertEqual(SettingsStore(defaults: defaults).hotkey, .default)

        defaults.set(Data(#"{"kind":{"modifier":{"_0":"leftPinky"}}}"#.utf8), forKey: SettingsStore.Keys.hotkey)
        XCTAssertEqual(SettingsStore(defaults: defaults).hotkey, .default)
    }

    func testACorruptValueIsReplacedOnTheNextWrite() {
        let defaults = makeDefaults()
        defaults.set("sometimes", forKey: SettingsStore.Keys.activationMode)
        let settings = SettingsStore(defaults: defaults)
        settings.activationMode = .toggle
        XCTAssertEqual(SettingsStore(defaults: defaults).activationMode, .toggle)
    }

    // MARK: - Helpers

    private var allKeys: [String] {
        [
            SettingsStore.Keys.hasCompletedOnboarding, SettingsStore.Keys.activeModelID,
            SettingsStore.Keys.languageCode, SettingsStore.Keys.hotkey, SettingsStore.Keys.activationMode,
            SettingsStore.Keys.insertionMethod, SettingsStore.Keys.restoreClipboardAfterPaste,
            SettingsStore.Keys.smartCapitalization, SettingsStore.Keys.smartSpacing,
            SettingsStore.Keys.voiceCommandsEnabled, SettingsStore.Keys.showHUD, SettingsStore.Keys.playSounds,
            SettingsStore.Keys.launchAtLogin, SettingsStore.Keys.inputDeviceID, SettingsStore.Keys.keepHistory,
            SettingsStore.Keys.hasSeenModelRecommendation, SettingsStore.Keys.showFieldMic,
            SettingsStore.Keys.dismissedUpgradeModelID,
        ]
    }
}

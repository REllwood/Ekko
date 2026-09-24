import AppKit
import AVFoundation

/// Application lifecycle. Wires the container to the UI layer and the system services.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var container: AppContainer!
    private var ui: UICoordinator!

    func applicationDidFinishLaunching(_ notification: Notification) {
        container = AppContainer.shared
        ui = UICoordinator(container: container)
        #if DEBUG
        runDebugDemo()
        #endif
        Log.app.info("Ekko launched (\(Bundle.main.shortVersion, privacy: .public)) on \(self.container.hardware.summary, privacy: .public)")

        // The menu bar item, HUD and dictation pipeline are always up, so the onboarding
        // "Try it" step works and permissions granted during onboarding are picked up live.
        container.permissions.refresh()
        ui.installStatusItem()
        ui.startHUD()
        ui.startFieldMic()
        container.dictation.start()

        if let debugPage = LaunchArguments.settingsPage {
            ui.showSettings(page: debugPage)
        } else if let debugStep = LaunchArguments.onboardingStep {
            ui.showOnboarding(startingAt: debugStep) { [weak self] in self?.container.dictation.preloadModelIfNeeded() }
        } else if !container.settings.hasCompletedOnboarding {
            ui.showOnboarding { [weak self] in
                guard let self else { return }
                Log.app.info("Onboarding finished; completed = \(self.container.settings.hasCompletedOnboarding, privacy: .public)")
                self.container.dictation.preloadModelIfNeeded()
            }
        }
    }

    /// Double-clicking Ekko in Finder while it is running opens Settings (or resumes onboarding).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if container.settings.hasCompletedOnboarding {
            ui.showSettings()
        } else {
            ui.showOnboarding { [weak self] in self?.container.dictation.preloadModelIfNeeded() }
        }
        return false
    }

    #if DEBUG
    /// `--demo-state listening|loading|transcribing|inserting|failed|nothing` and `--show-popover`
    /// put the UI in a state that normally needs a microphone, a model and permissions.
    private func runDebugDemo() {
        let arguments = CommandLine.arguments
        if let raw = LaunchArguments.value(after: "--demo-state") {
            let dictation = container.dictation
            let levels: [Float] = (0..<24).map { index in
                let wave = (sin(Double(index) * 0.55) + 1) / 2
                return Float(0.15 + wave * 0.7)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                switch raw {
                case "listening":
                    dictation.debugSimulate(state: .listening, listeningFor: 7)
                    self?.container.audio.debugSimulate(levels: levels)
                case "loading": dictation.debugSimulate(state: .preparing, modelLoading: 0.55)
                case "transcribing": dictation.debugSimulate(state: .transcribing)
                case "inserting": dictation.debugSimulate(state: .inserting)
                case "failed": dictation.debugSimulate(state: .failed(.insertionFailed("Copied to clipboard")))
                case "nothing": dictation.debugSimulate(state: .failed(.nothingHeard))
                default: break
                }
            }
        }
        if arguments.contains("--demo-field-mic"), let screen = NSScreen.main {
            // A pretend single-line field in the middle of the main screen.
            let field = CGRect(x: screen.visibleFrame.midX - 160, y: screen.visibleFrame.midY, width: 320, height: 24)
            FieldMicController.debugTarget = EditableTarget(
                appPID: 0, appBundleID: nil, elementFrame: field, caretRect: nil, windowFrame: nil, isMultiline: false
            )
        }
        if let directory = LaunchArguments.value(after: "--export-status-icons") {
            // Renders the menu-bar icon states at 4x so they can be inspected without a menu bar.
            let frames: [(String, NSImage)] = [("idle", StatusItemIcon.idle)]
                + (0..<StatusItemIcon.frameCount).map { ("listening-\($0)", StatusItemIcon.listening(frame: $0, level: 0.5)) }
                + [("transcribing-3", StatusItemIcon.transcribing(frame: 3))]
            for (name, image) in frames {
                let size = NSSize(width: image.size.width * 4, height: image.size.height * 4)
                let rep = NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
                )
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = rep.flatMap(NSGraphicsContext.init(bitmapImageRep:))
                image.draw(in: NSRect(origin: .zero, size: size))
                NSGraphicsContext.restoreGraphicsState()
                try? rep?.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
            }
            NSApp.terminate(nil)
        }
        if let modelID = LaunchArguments.value(after: "--debug-download") {
            Log.app.info("Debug: downloading \(modelID, privacy: .public)")
            container.modelManager.download(modelID)
        }
        if let path = LaunchArguments.value(after: "--debug-dictate-file") {
            runDebugDictation(file: URL(fileURLWithPath: path))
        }
        if arguments.contains("--show-popover") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.ui.showPopover() }
        }
    }

    /// Waits for a loaded model, then feeds a 16 kHz mono WAV through the dictation pipeline.
    private func runDebugDictation(file: URL) {
        let container = self.container!
        Task { @MainActor in
            let deadline = Date().addingTimeInterval(600)
            while !container.dictation.isModelLoaded, Date() < deadline {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            guard container.dictation.isModelLoaded else {
                Log.app.error("Debug: model never loaded")
                return
            }
            guard let audioFile = try? AVAudioFile(forReading: file),
                  let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: AVAudioFrameCount(audioFile.length)),
                  (try? audioFile.read(into: buffer)) != nil,
                  let channel = buffer.floatChannelData?[0] else {
                Log.app.error("Debug: could not read \(file.path, privacy: .public)")
                return
            }
            let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            Log.app.info("Debug: dictating \(samples.count) samples")
            container.dictation.debugDictate(AudioBuffer16k(samples: samples))
        }
    }
    #endif

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        container.dictation.stop()
        Log.app.info("Ekko terminating")
    }
}

/// Developer conveniences: `Ekko --show-settings models` or `Ekko --onboarding-step 2`.
enum LaunchArguments {
    static var settingsPage: SettingsPage? {
        value(after: "--show-settings").flatMap(SettingsPage.init(rawValue:))
    }

    static var onboardingStep: Int? {
        value(after: "--onboarding-step").flatMap(Int.init)
    }

    static func value(after flag: String) -> String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}

extension Bundle {
    var shortVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }
}

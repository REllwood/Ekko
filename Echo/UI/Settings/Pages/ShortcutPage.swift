import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
struct ShortcutPage: View {
    let container: AppContainer

    @State private var isCapturing = false

    private static let presets: [(label: String, hotkey: Hotkey)] = [
        ("Right ⌥", Hotkey(kind: .modifier(.rightOption))),
        ("Fn", Hotkey(kind: .modifier(.fn))),
        ("⌥ Space", Hotkey(kind: .combo(keyCode: UInt16(kVK_Space), modifiers: NSEvent.ModifierFlags.option.rawValue))),
        ("⌃ Space", Hotkey(kind: .combo(keyCode: UInt16(kVK_Space), modifiers: NSEvent.ModifierFlags.control.rawValue))),
    ]

    var body: some View {
        @Bindable var settings = container.settings

        VStack(alignment: .leading, spacing: EchoSpacing.xl) {
            EchoCard {
                VStack(alignment: .leading, spacing: EchoSpacing.m) {
                    SectionHeader(title: "Your shortcut")
                    if isCapturing {
                        capturePrompt
                    } else {
                        HStack(spacing: EchoSpacing.m) {
                            KeyCapRow(hotkey: settings.hotkey, size: 15)
                            Spacer(minLength: 0)
                            Button("Change…") { beginCapture() }
                                .buttonStyle(.echoSecondary())
                                .accessibilityLabel(Text("Change dictation shortcut"))
                        }
                    }

                    if let reason = container.hotkeys.lastCaptureRejectionReason, !isCapturing {
                        Text(reason)
                            .font(EchoType.caption)
                            .foregroundStyle(EchoColor.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let error = container.hotkeys.lastError {
                        Text(error.localizedDescription)
                            .font(EchoType.caption)
                            .foregroundStyle(EchoColor.live)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            VStack(alignment: .leading, spacing: EchoSpacing.s) {
                SectionHeader(title: "Quick presets")
                HStack(spacing: EchoSpacing.s) {
                    ForEach(Self.presets, id: \.label) { preset in
                        Button(preset.label) { settings.hotkey = preset.hotkey }
                            .buttonStyle(.echoSecondary())
                            .disabled(settings.hotkey == preset.hotkey)
                            .accessibilityLabel(Text("Use \(preset.label) as the dictation shortcut"))
                    }
                    Spacer(minLength: 0)
                }
            }

            if isFnSelected {
                fnTip
            }

            VStack(alignment: .leading, spacing: EchoSpacing.s) {
                SectionHeader(title: "When you press it")
                Picker("", selection: $settings.activationMode) {
                    ForEach(ActivationMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel(Text("Activation mode"))
                Text(settings.activationMode.detail)
                    .font(EchoType.caption)
                    .foregroundStyle(EchoColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear {
            if isCapturing {
                container.hotkeys.cancelCapture()
                isCapturing = false
            }
        }
    }

    private var capturePrompt: some View {
        HStack(spacing: EchoSpacing.m) {
            StatusDot(state: .live, size: 8, pulses: true)
            Text("Press your new shortcut… (Esc to cancel)")
                .font(EchoType.body)
                .foregroundStyle(EchoColor.ink)
            Spacer(minLength: 0)
            Button("Cancel") {
                container.hotkeys.cancelCapture()
                isCapturing = false
            }
            .buttonStyle(.echoQuiet(size: .small))
            .accessibilityLabel(Text("Cancel shortcut capture"))
        }
        .padding(EchoSpacing.m)
        .background(EchoColor.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: EchoRadius.control, style: .continuous))
        .accessibilityLabel(Text("Press your new shortcut. Press escape to cancel."))
    }

    private var isFnSelected: Bool {
        if case .modifier(.fn) = container.settings.hotkey.kind { return true }
        return false
    }

    private var fnTip: some View {
        HStack(alignment: .top, spacing: EchoSpacing.s) {
            Image(systemName: "lightbulb")
                .font(.system(size: 12))
                .foregroundStyle(EchoColor.warning)
            VStack(alignment: .leading, spacing: EchoSpacing.xxs) {
                Text("One setting to change for the 🌐 key")
                    .font(EchoType.bodyMedium)
                    .foregroundStyle(EchoColor.ink)
                Text("Open System Settings › Keyboard and set “Press 🌐 key to” to “Do Nothing”, otherwise macOS opens the input-source picker when you press it.")
                    .font(EchoType.caption)
                    .foregroundStyle(EchoColor.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(EchoSpacing.m)
        .background(EchoColor.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: EchoRadius.control, style: .continuous))
    }

    private func beginCapture() {
        isCapturing = true
        container.hotkeys.beginCapture { captured in
            isCapturing = false
            guard let captured else { return }
            container.settings.hotkey = captured
            Log.ui.info("Shortcut changed to \(captured.displayString, privacy: .public)")
        }
    }
}

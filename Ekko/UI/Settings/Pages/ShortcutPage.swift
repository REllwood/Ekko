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

        VStack(alignment: .leading, spacing: EkkoSpacing.section) {
            VStack(alignment: .leading, spacing: EkkoSpacing.s) {
                SectionHeader(title: "Your shortcut")
                EkkoCard {
                    VStack(alignment: .leading, spacing: EkkoSpacing.m) {
                        if isCapturing {
                            capturePrompt
                        } else {
                            HStack(spacing: EkkoSpacing.m) {
                                KeyCapRow(hotkey: settings.hotkey, size: 15)
                                Spacer(minLength: 0)
                                Button("Change…") { beginCapture() }
                                    .buttonStyle(.ekkoSecondary())
                                    .accessibilityLabel(Text("Change dictation shortcut"))
                            }
                        }

                        if let reason = container.hotkeys.lastCaptureRejectionReason, !isCapturing {
                            Label(reason, systemImage: "exclamationmark.circle")
                                .font(EkkoType.caption)
                                .foregroundStyle(EkkoColor.warningText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let error = container.hotkeys.lastError {
                            Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                                .font(EkkoType.caption)
                                .foregroundStyle(EkkoColor.dangerText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: EkkoSpacing.s) {
                SectionHeader(title: "Quick presets")
                HStack(spacing: EkkoSpacing.s) {
                    ForEach(Self.presets, id: \.label) { preset in
                        PresetButton(label: preset.label, isSelected: settings.hotkey == preset.hotkey) {
                            settings.hotkey = preset.hotkey
                        }
                    }
                    Spacer(minLength: 0)
                }
                if isFnSelected {
                    fnTip
                }
            }

            VStack(alignment: .leading, spacing: EkkoSpacing.s) {
                SectionHeader(title: "When you press it")
                EkkoCard(padding: EkkoSpacing.s) {
                    EkkoRadioGroup(
                        selection: $settings.activationMode,
                        options: ActivationMode.allCases,
                        title: \.title,
                        detail: \.detail
                    )
                }
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
        HStack(spacing: EkkoSpacing.m) {
            StatusDot(state: .live, size: 8, pulses: true)
            Text("Press your new shortcut… (Esc to cancel)")
                .font(EkkoType.body)
                .foregroundStyle(EkkoColor.ink)
            Spacer(minLength: 0)
            Button("Cancel") {
                container.hotkeys.cancelCapture()
                isCapturing = false
            }
            .buttonStyle(.ekkoQuiet(size: .small))
            .accessibilityLabel(Text("Cancel shortcut capture"))
        }
        .padding(EkkoSpacing.m)
        .background(EkkoColor.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: EkkoRadius.control, style: .continuous))
        .accessibilityLabel(Text("Press your new shortcut. Press escape to cancel."))
    }

    private var isFnSelected: Bool {
        if case .modifier(.fn) = container.settings.hotkey.kind { return true }
        return false
    }

    private var fnTip: some View {
        EkkoNotice(
            icon: "lightbulb.fill",
            tint: EkkoColor.warning,
            title: "One setting to change for the 🌐 key",
            message: "Open System Settings › Keyboard and set “Press 🌐 key to” to “Do Nothing”, otherwise macOS opens the input-source picker when you press it."
        )
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

/// A shortcut preset. The one in use is shown as selected (tinted, bordered, ticked), not disabled.
private struct PresetButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: EkkoRadius.control, style: .continuous) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                }
                Text(label)
                    .font(EkkoType.bodyMedium)
            }
            .foregroundStyle(isSelected ? EkkoColor.accentText : EkkoColor.ink)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(isSelected ? EkkoColor.accent.opacity(0.10) : (isHovering ? EkkoColor.surfaceMuted : EkkoColor.surface), in: shape)
            .overlay(shape.strokeBorder(isSelected ? EkkoColor.accent.opacity(0.7) : EkkoColor.hairlineStrong, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(Text(isSelected ? "\(label), current shortcut" : "Use \(label) as the dictation shortcut"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

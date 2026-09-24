import AppKit
import SwiftUI

/// Contents of the menu-bar popover. 320 pt wide, sized to fit.
@MainActor
struct MenuBarView: View {
    let container: AppContainer
    let openSettings: (SettingsPage) -> Void
    let toggleDictation: () -> Void
    let quit: () -> Void

    @State private var didCopy = false

    private var dictation: DictationController { container.dictation }
    private var settings: SettingsStore { container.settings }

    var body: some View {
        VStack(spacing: 0) {
            header
            EchoDivider()
            content
            EchoDivider()
            footer
        }
        .frame(width: 320)
        .background(EchoColor.page)
    }

    // MARK: - Header

    private var header: some View {
        let state = dictation.state
        return VStack(alignment: .leading, spacing: EchoSpacing.xs) {
            HStack(spacing: EchoSpacing.s) {
                StatusDot(state: DictationPresentation.dot(for: state), size: 7, pulses: state.isListening)
                Text(DictationPresentation.title(for: state, isModelLoading: dictation.isModelLoading))
                    .font(EchoType.bodySemibold)
                    .foregroundStyle(EchoColor.ink)
                Spacer(minLength: EchoSpacing.s)
                if state.isListening {
                    Text(DictationPresentation.elapsedString(dictation.listeningDuration))
                        .font(EchoType.mono)
                        .foregroundStyle(EchoColor.inkMuted)
                        .monospacedDigit()
                }
            }
            Text(DictationPresentation.detail(for: state) ?? "Everything runs on this Mac.")
                .font(EchoType.caption)
                .foregroundStyle(EchoColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(EchoSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Body

    private var content: some View {
        VStack(alignment: .leading, spacing: EchoSpacing.m) {
            primaryButton
            if dictation.state.isListening {
                LevelBars(
                    levels: container.audio.levelHistory,
                    barCount: 24,
                    maxHeight: 18,
                    tint: EchoColor.live,
                    isActive: true
                )
                .frame(maxWidth: .infinity)
            } else {
                shortcutHint
            }
            chips
            modelCards
            if !container.permissions.allGranted {
                permissionsWarning
            }
            if let transcript = dictation.lastTranscript {
                lastTranscript(transcript)
            }
        }
        .padding(EchoSpacing.l)
    }

    private var primaryButton: some View {
        let listening = dictation.state.isListening
        return Button {
            toggleDictation()
        } label: {
            HStack(spacing: EchoSpacing.s) {
                Image(systemName: listening ? "stop.fill" : "mic.fill")
                Text(listening ? "Stop" : "Start dictating")
            }
        }
        .buttonStyle(.echoPrimary(fullWidth: true, size: .large, tint: listening ? EchoColor.live : EchoColor.accent))
        .accessibilityLabel(Text(listening ? "Stop dictating" : "Start dictating"))
    }

    private var shortcutHint: some View {
        HStack(spacing: EchoSpacing.s) {
            Text("or press")
                .font(EchoType.caption)
                .foregroundStyle(EchoColor.inkMuted)
            KeyCapRow(hotkey: settings.hotkey, size: 11)
            Spacer(minLength: 0)
        }
    }

    private var chips: some View {
        HStack(spacing: EchoSpacing.s) {
            EchoChip(icon: "cpu", text: modelName) { openSettings(.models) }
            EchoChip(icon: "globe", text: DictationPresentation.languageLabel(for: settings.languageCode)) {
                openSettings(.languages)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var modelCards: some View {
        if dictation.isModelLoading, !dictation.state.isActive {
            ModelLoadingNote(progress: dictation.modelLoadProgress)
        }
        if container.modelManager.activeModel == nil {
            ChooseModelCard(recommended: recommendation.recommended) { openSettings(.models) }
        } else if let upgrade = ModelRecommender.upgradeSuggestion(
            active: container.modelManager.activeModel,
            hardware: container.hardware,
            languageCode: settings.languageCode,
            dismissedID: settings.dismissedUpgradeModelID
        ) {
            UpgradeModelCard(container: container, model: upgrade)
        }
    }

    private var recommendation: ModelRecommendation {
        ModelRecommender.recommendation(for: container.hardware, preferEnglishOnly: settings.isEnglish)
    }

    private var modelName: String {
        guard let id = settings.activeModelID, let model = ModelCatalog.descriptor(for: id) else {
            return "No model"
        }
        return model.displayName
    }

    private var permissionsWarning: some View {
        HStack(alignment: .top, spacing: EchoSpacing.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(EchoColor.warning)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(missingPermissionsTitle)
                    .font(EchoType.captionMedium)
                    .foregroundStyle(EchoColor.ink)
                Text("Echo can't hear you or type for you until this is granted.")
                    .font(EchoType.caption)
                    .foregroundStyle(EchoColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: EchoSpacing.s)
            Button("Fix") { openSettings(.permissions) }
                .buttonStyle(.echoSecondary(size: .small))
                .accessibilityLabel(Text("Fix permissions"))
        }
        .padding(EchoSpacing.m)
        .background(EchoColor.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: EchoRadius.control, style: .continuous))
    }

    private var missingPermissionsTitle: String {
        let missing = Permission.allCases.filter { status(for: $0) != .granted }.map(\.title)
        if missing.isEmpty { return "Permissions needed" }
        return "\(missing.joined(separator: " and ")) access needed"
    }

    private func status(for permission: Permission) -> PermissionStatus {
        switch permission {
        case .microphone: return container.permissions.microphone
        case .accessibility: return container.permissions.accessibility
        }
    }

    private func lastTranscript(_ entry: TranscriptEntry) -> some View {
        VStack(alignment: .leading, spacing: EchoSpacing.s) {
            HStack {
                Text("Last transcription")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(EchoColor.inkMuted)
                Spacer()
                Button(didCopy ? "Copied" : "Copy") { copy(entry.text) }
                    .buttonStyle(.echoQuiet(size: .small, tint: EchoColor.accent))
                    .accessibilityLabel(Text("Copy last transcription"))
            }
            Text(entry.text)
                .font(EchoType.footnote)
                .foregroundStyle(EchoColor.inkSoft)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(EchoSpacing.m)
        .background(EchoColor.surface, in: RoundedRectangle(cornerRadius: EchoRadius.control, style: .continuous))
        .echoHairlineBorder(radius: EchoRadius.control)
    }

    private func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        didCopy = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            didCopy = false
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: EchoSpacing.s) {
            Button("Settings") { openSettings(.general) }
                .buttonStyle(.echoQuiet(size: .small))
                .keyboardShortcut(",", modifiers: .command)
                .accessibilityLabel(Text("Open settings"))
            Spacer()
            Button("Quit", action: quit)
                .buttonStyle(.echoQuiet(size: .small))
                .keyboardShortcut("q", modifiers: .command)
                .accessibilityLabel(Text("Quit Echo"))
        }
        .padding(.horizontal, EchoSpacing.m)
        .padding(.vertical, EchoSpacing.s)
    }
}

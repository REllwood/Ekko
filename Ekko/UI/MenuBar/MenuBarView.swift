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
            EkkoDivider()
            content
            EkkoDivider()
            footer
        }
        .frame(width: 320)
        .background(EkkoColor.page)
    }

    // MARK: - Header

    private var header: some View {
        let state = dictation.state
        return VStack(alignment: .leading, spacing: EkkoSpacing.xs) {
            HStack(spacing: EkkoSpacing.s) {
                StatusDot(state: DictationPresentation.dot(for: state), size: 7, pulses: state.isListening)
                Text(DictationPresentation.title(for: state, isModelLoading: dictation.isModelLoading))
                    .font(EkkoType.bodySemibold)
                    .foregroundStyle(EkkoColor.ink)
                Spacer(minLength: EkkoSpacing.s)
                if state.isListening {
                    Text(DictationPresentation.elapsedString(dictation.listeningDuration))
                        .font(EkkoType.mono)
                        .foregroundStyle(EkkoColor.inkMuted)
                        .monospacedDigit()
                }
            }
            Text(DictationPresentation.detail(for: state) ?? "Everything runs on this Mac.")
                .font(EkkoType.caption)
                .foregroundStyle(EkkoColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(EkkoSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Body

    private var content: some View {
        VStack(alignment: .leading, spacing: EkkoSpacing.m) {
            primaryButton
            if dictation.state.isListening {
                LevelBars(
                    levels: container.audio.levelHistory,
                    barCount: 24,
                    maxHeight: 18,
                    tint: EkkoColor.live,
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
        .padding(EkkoSpacing.l)
    }

    private var primaryButton: some View {
        let listening = dictation.state.isListening
        return Button {
            toggleDictation()
        } label: {
            HStack(spacing: EkkoSpacing.s) {
                Image(systemName: listening ? "stop.fill" : "mic.fill")
                Text(listening ? "Stop" : "Start dictating")
            }
        }
        .buttonStyle(.ekkoPrimary(fullWidth: true, size: .large, tint: listening ? EkkoColor.live : EkkoColor.accentFill))
        .accessibilityLabel(Text(listening ? "Stop dictating" : "Start dictating"))
    }

    private var shortcutHint: some View {
        HStack(spacing: EkkoSpacing.s) {
            Text("or press")
                .font(EkkoType.caption)
                .foregroundStyle(EkkoColor.inkMuted)
            KeyCapRow(hotkey: settings.hotkey, size: 11)
            Spacer(minLength: 0)
        }
    }

    private var chips: some View {
        HStack(spacing: EkkoSpacing.s) {
            EkkoChip(icon: "cpu", text: modelName) { openSettings(.models) }
            EkkoChip(icon: "globe", text: DictationPresentation.languageLabel(for: settings.languageCode)) {
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

    /// The one real blocker, so it gets the strong treatment and a primary button.
    private var permissionsWarning: some View {
        EkkoNotice(
            icon: "exclamationmark.triangle.fill",
            tint: EkkoColor.warning,
            title: missingPermissionsTitle,
            message: "Ekko can't hear you or type for you until this is granted.",
            emphasis: .strong
        ) {
            Button("Fix") { openSettings(.permissions) }
                .buttonStyle(.ekkoPrimary(size: .small))
                .accessibilityLabel(Text("Fix permissions"))
        }
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
        VStack(alignment: .leading, spacing: EkkoSpacing.s) {
            HStack {
                Text("Last transcription")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(EkkoColor.inkMuted)
                Spacer()
                Button(didCopy ? "Copied" : "Copy") { copy(entry.text) }
                    .buttonStyle(.ekkoLink(tint: EkkoColor.accentText, font: EkkoType.captionMedium))
                    .accessibilityLabel(Text("Copy last transcription"))
            }
            Text(entry.text)
                .font(EkkoType.footnote)
                .foregroundStyle(EkkoColor.inkSoft)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(EkkoSpacing.m)
        .background(EkkoColor.surface, in: RoundedRectangle(cornerRadius: EkkoRadius.control, style: .continuous))
        .ekkoHairlineBorder(radius: EkkoRadius.control)
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
        HStack(spacing: EkkoSpacing.s) {
            Button("Settings…") { openSettings(.general) }
                .buttonStyle(.ekkoLink(font: EkkoType.captionMedium))
                .keyboardShortcut(",", modifiers: .command)
                .accessibilityLabel(Text("Open settings"))
            Spacer()
            Button("Quit Ekko", action: quit)
                .buttonStyle(.ekkoLink(font: EkkoType.captionMedium))
                .keyboardShortcut("q", modifiers: .command)
                .accessibilityLabel(Text("Quit Ekko"))
        }
        .padding(.horizontal, EkkoSpacing.l)
        .padding(.vertical, EkkoSpacing.xs)
    }
}

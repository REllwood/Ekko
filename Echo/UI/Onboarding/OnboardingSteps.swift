import SwiftUI

// MARK: - 1. Welcome

struct OnboardingWelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: EchoSpacing.l) {
            Image(systemName: "waveform")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(EchoColor.accent)
                .accessibilityHidden(true)

            Text("Speak anywhere.\nEcho types it for you.")
                .font(EchoType.hero)
                .foregroundStyle(EchoColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text("""
            Press one key, say what you mean, and the words appear wherever your cursor is — \
            in Mail, in a browser form, in your editor, in a terminal. Echo transcribes on this \
            Mac: no account, no network, nothing to opt out of.
            """)
            .font(EchoType.heroSub)
            .foregroundStyle(EchoColor.inkSoft)
            .fixedSize(horizontal: false, vertical: true)

            Text("Setting up takes about a minute.")
                .font(EchoType.footnote)
                .foregroundStyle(EchoColor.inkMuted)
        }
        .padding(.top, EchoSpacing.s)
    }
}

// MARK: - 2. Permissions

@MainActor
struct OnboardingPermissionsStep: View {
    let container: AppContainer
    @Binding var showSkipWarning: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: EchoSpacing.l) {
            OnboardingHeading(
                title: "Two permissions, nothing more",
                subtitle: "macOS asks you directly. Echo never sees anything beyond what it needs to hear you and type for you."
            )

            EchoCard {
                VStack(spacing: EchoSpacing.s) {
                    PermissionRow(
                        permission: .microphone,
                        status: container.permissions.microphone,
                        grant: { Task { await container.permissions.requestMicrophone() } },
                        openSystemSettings: { container.permissions.openSystemSettings(for: .microphone) }
                    )
                    EchoDivider()
                    PermissionRow(
                        permission: .accessibility,
                        status: container.permissions.accessibility,
                        grant: { container.permissions.promptAccessibility() },
                        openSystemSettings: { container.permissions.openSystemSettings(for: .accessibility) }
                    )
                }
            }

            if showSkipWarning {
                HStack(alignment: .top, spacing: EchoSpacing.s) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(EchoColor.warning)
                    Text("Without these, Echo can't hear you or type into other apps. You can grant them later in Settings › Permissions.")
                        .font(EchoType.caption)
                        .foregroundStyle(EchoColor.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(EchoSpacing.m)
                .background(EchoColor.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: EchoRadius.control, style: .continuous))
            }
        }
        .onAppear {
            container.permissions.refresh()
            container.permissions.startMonitoring()
        }
    }
}

// MARK: - 3. Model

@MainActor
struct OnboardingModelStep: View {
    let container: AppContainer
    @Binding var selectedModelID: ModelID?

    @State private var showAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: EchoSpacing.l) {
            OnboardingHeading(
                title: "Choose your speech model",
                subtitle: "Downloaded once, then it runs offline. You can change this later."
            )

            OnboardingModelOption(
                model: recommendation.recommended,
                container: container,
                isSelected: selectedModelID == recommendation.recommended.id,
                headline: recommendation.headline,
                rationale: recommendation.rationale
            ) {
                selectedModelID = recommendation.recommended.id
            }

            if let id = selectedModelID, case .downloading(let fraction, _, _) = container.modelManager.state(for: id) {
                VStack(alignment: .leading, spacing: EchoSpacing.xs) {
                    EchoProgressBar(fraction: fraction)
                    Text("Downloading… \(Int((fraction * 100).rounded()))%")
                        .font(EchoType.caption)
                        .foregroundStyle(EchoColor.inkMuted)
                }
            }

            Button(showAll ? "Hide other models" : "See all models") { showAll.toggle() }
                .buttonStyle(.echoQuiet(size: .small, tint: EchoColor.accent))
                .accessibilityLabel(Text(showAll ? "Hide other models" : "See all models"))

            if showAll {
                VStack(spacing: EchoSpacing.s) {
                    ForEach(otherModels) { model in
                        OnboardingModelOption(
                            model: model,
                            container: container,
                            isSelected: selectedModelID == model.id,
                            headline: model.displayName,
                            rationale: model.summary
                        ) {
                            selectedModelID = model.id
                        }
                    }
                }
            }
        }
        .onAppear { container.modelManager.refresh() }
    }

    private var recommendation: ModelRecommendation {
        ModelRecommender.recommendation(
            for: container.hardware,
            preferEnglishOnly: container.settings.isEnglish
        )
    }

    private var otherModels: [ModelDescriptor] {
        ModelCatalog.all.filter { $0.id != recommendation.recommended.id }
    }
}

@MainActor
struct OnboardingModelOption: View {
    let model: ModelDescriptor
    let container: AppContainer
    let isSelected: Bool
    let headline: String
    let rationale: String
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            EchoCard(highlighted: isSelected) {
                VStack(alignment: .leading, spacing: EchoSpacing.s) {
                    HStack(spacing: EchoSpacing.s) {
                        Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(isSelected ? EchoColor.accent : EchoColor.hairlineStrong)
                        Text(model.displayName)
                            .font(EchoType.bodySemibold)
                            .foregroundStyle(EchoColor.ink)
                        EchoBadge(text: model.sizeLabel, tone: .neutral)
                        if container.modelManager.state(for: model.id).isInstalled {
                            EchoBadge(text: "Installed", tone: .success, icon: "checkmark")
                        }
                        Spacer(minLength: 0)
                    }
                    Text(headline)
                        .font(EchoType.body)
                        .foregroundStyle(EchoColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if !rationale.isEmpty {
                        Text(rationale)
                            .font(EchoType.caption)
                            .foregroundStyle(EchoColor.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(model.displayName))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - 4. Try it

@MainActor
struct OnboardingTryStep: View {
    let container: AppContainer

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: EchoSpacing.l) {
            OnboardingHeading(
                title: "Try it here",
                subtitle: "Click in the box below, then click the mic or press your shortcut, and say something. Click or press again when you're done."
            )

            HStack(spacing: EchoSpacing.s) {
                KeyCapRow(hotkey: container.settings.hotkey, size: 13)
                Text(container.settings.activationMode.detail)
                    .font(EchoType.caption)
                    .foregroundStyle(EchoColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            TextEditor(text: $text)
                .font(EchoType.body)
                .scrollContentBackground(.hidden)
                .padding(EchoSpacing.s)
                .padding(.trailing, 36)
                .frame(height: 140)
                .background(EchoColor.surface, in: RoundedRectangle(cornerRadius: EchoRadius.card, style: .continuous))
                .echoHairlineBorder(radius: EchoRadius.card, color: isFocused ? EchoColor.accent : EchoColor.hairline)
                .focused($isFocused)
                .accessibilityLabel(Text("Practice text field"))
                .overlay(alignment: .bottomTrailing) {
                    PracticeMicButton(container: container) { isFocused = true }
                        .padding(EchoSpacing.s)
                }

            HStack(spacing: EchoSpacing.s) {
                StatusDot(
                    state: DictationPresentation.dot(for: container.dictation.state),
                    size: 8,
                    pulses: container.dictation.state.isListening
                )
                Text(DictationPresentation.title(for: container.dictation.state, isModelLoading: container.dictation.isModelLoading))
                    .font(EchoType.footnote)
                    .foregroundStyle(EchoColor.inkSoft)
                Spacer(minLength: 0)
                if container.dictation.state.isListening {
                    LevelBars(
                        levels: container.audio.levelHistory,
                        barCount: 16,
                        maxHeight: 14,
                        tint: EchoColor.live
                    )
                }
            }

            if container.dictation.isModelLoading {
                ModelLoadingNote(progress: container.dictation.modelLoadProgress)
            }
        }
        .onAppear { isFocused = true }
    }
}

/// The same click-to-dictate affordance Echo shows beside text fields in other apps, built into
/// the practice box (Echo does not float its field mic over its own windows).
@MainActor
private struct PracticeMicButton: View {
    let container: AppContainer
    /// Keeps the practice box focused so the transcript lands in it.
    let refocus: () -> Void

    @State private var isHovering = false

    private var state: DictationState { container.dictation.state }

    var body: some View {
        Button {
            refocus()
            container.dictation.toggle()
        } label: {
            ZStack {
                Circle()
                    .fill(state.isListening ? EchoColor.live : (isHovering ? EchoColor.accent.opacity(0.14) : EchoColor.surfaceMuted))
                Circle()
                    .strokeBorder(state.isListening ? Color.clear : EchoColor.hairlineStrong, lineWidth: 1)
                if state == .preparing || state == .transcribing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: state.isListening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(state.isListening ? Color.white : (isHovering ? EchoColor.accent : EchoColor.inkSoft))
                }
            }
            .frame(width: 28, height: 28)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { isHovering = $0 }
        .help(state.isListening ? "Stop dictating" : "Click to dictate")
        .accessibilityLabel(Text(state.isListening ? "Stop dictating" : "Dictate into the practice box"))
    }
}

// MARK: - Shared

struct OnboardingHeading: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: EchoSpacing.xs) {
            Text(title)
                .font(EchoType.pageTitle)
                .foregroundStyle(EchoColor.ink)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(EchoType.footnote)
                .foregroundStyle(EchoColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

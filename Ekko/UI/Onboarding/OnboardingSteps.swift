import SwiftUI

// MARK: - 1. Welcome

struct OnboardingWelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: EkkoSpacing.l) {
            EkkoAppIcon(size: 64)
                .padding(.leading, -6) // the icon artwork has its own transparent margin

            Text("Speak anywhere.\nEkko types it for you.")
                .font(EkkoType.hero)
                .foregroundStyle(EkkoColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text("""
            Press one key, say what you mean, and the words appear wherever your cursor is — \
            in Mail, in a browser form, in your editor, in a terminal. Ekko transcribes on this \
            Mac: no account, no network, nothing to opt out of.
            """)
            .font(EkkoType.heroSub)
            .foregroundStyle(EkkoColor.inkSoft)
            .fixedSize(horizontal: false, vertical: true)

            Text("Setting up takes about a minute.")
                .font(EkkoType.footnote)
                .foregroundStyle(EkkoColor.inkMuted)
        }
        .padding(.top, EkkoSpacing.s)
        // Sit in the middle of the step area instead of leaving the lower half empty.
        .frame(maxWidth: .infinity, minHeight: 330, alignment: .leading)
    }
}

// MARK: - 2. Permissions

@MainActor
struct OnboardingPermissionsStep: View {
    let container: AppContainer
    @Binding var showSkipWarning: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: EkkoSpacing.l) {
            OnboardingHeading(
                title: "Two permissions, nothing more",
                subtitle: "macOS asks you directly. Ekko never sees anything beyond what it needs to hear you and type for you."
            )

            EkkoCard {
                VStack(spacing: EkkoSpacing.s) {
                    PermissionRow(
                        permission: .microphone,
                        status: container.permissions.microphone,
                        grant: { Task { await container.permissions.requestMicrophone() } },
                        openSystemSettings: { container.permissions.openSystemSettings(for: .microphone) }
                    )
                    EkkoDivider()
                    PermissionRow(
                        permission: .accessibility,
                        status: container.permissions.accessibility,
                        grant: { container.permissions.promptAccessibility() },
                        openSystemSettings: { container.permissions.openSystemSettings(for: .accessibility) }
                    )
                }
            }

            if showSkipWarning {
                EkkoNotice(
                    icon: "exclamationmark.triangle.fill",
                    tint: EkkoColor.warning,
                    message: "Without these, Ekko can't hear you or type into other apps. You can grant them later in Settings › Permissions.",
                    emphasis: .strong
                )
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
        VStack(alignment: .leading, spacing: EkkoSpacing.l) {
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
                VStack(alignment: .leading, spacing: EkkoSpacing.xs) {
                    EkkoProgressBar(fraction: fraction)
                    Text("Downloading… \(Int((fraction * 100).rounded()))%")
                        .font(EkkoType.caption)
                        .foregroundStyle(EkkoColor.inkMuted)
                }
            }

            Button(showAll ? "Hide other models" : "See all models") {
                withAnimation(.easeOut(duration: 0.2)) { showAll.toggle() }
            }
                .buttonStyle(.ekkoLink(tint: EkkoColor.accentText))
                .accessibilityLabel(Text(showAll ? "Hide other models" : "See all models"))

            if showAll {
                VStack(spacing: EkkoSpacing.s) {
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
            EkkoCard(highlighted: isSelected) {
                VStack(alignment: .leading, spacing: EkkoSpacing.s) {
                    HStack(spacing: EkkoSpacing.s) {
                        Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(isSelected ? EkkoColor.accent : EkkoColor.hairlineStrong)
                        Text(model.displayName)
                            .font(EkkoType.bodySemibold)
                            .foregroundStyle(EkkoColor.ink)
                        EkkoBadge(text: model.sizeLabel, tone: .neutral)
                        if container.modelManager.state(for: model.id).isInstalled {
                            EkkoBadge(text: "Installed", tone: .success, icon: "checkmark")
                        }
                        Spacer(minLength: 0)
                    }
                    Text(headline)
                        .font(EkkoType.body)
                        .foregroundStyle(EkkoColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if !rationale.isEmpty {
                        Text(rationale)
                            .font(EkkoType.caption)
                            .foregroundStyle(EkkoColor.inkMuted)
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
    @State private var celebrate = false
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var borderColor: Color {
        if celebrate { return EkkoColor.success }
        return isFocused ? EkkoColor.accent : EkkoColor.hairline
    }

    var body: some View {
        VStack(alignment: .leading, spacing: EkkoSpacing.l) {
            OnboardingHeading(
                title: "Try it here",
                subtitle: "Click in the box below, then click the mic or press your shortcut, and say something. Click or press again when you're done."
            )

            HStack(spacing: EkkoSpacing.s) {
                KeyCapRow(hotkey: container.settings.hotkey, size: 13)
                Text(container.settings.activationMode.detail)
                    .font(EkkoType.caption)
                    .foregroundStyle(EkkoColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            TextEditor(text: $text)
                .font(EkkoType.body)
                .scrollContentBackground(.hidden)
                .padding(EkkoSpacing.s)
                .padding(.trailing, 36)
                .frame(height: 140)
                .background(EkkoColor.surface, in: RoundedRectangle(cornerRadius: EkkoRadius.card, style: .continuous))
                .ekkoHairlineBorder(radius: EkkoRadius.card, color: borderColor)
                .animation(.easeOut(duration: 0.25), value: celebrate)
                .focused($isFocused)
                .accessibilityLabel(Text("Practice text field"))
                .overlay(alignment: .bottomTrailing) {
                    PracticeMicButton(container: container) { isFocused = true }
                        .padding(EkkoSpacing.s)
                }

            HStack(spacing: EkkoSpacing.s) {
                StatusDot(
                    state: DictationPresentation.dot(for: container.dictation.state),
                    size: 8,
                    pulses: container.dictation.state.isListening
                )
                Text(DictationPresentation.title(for: container.dictation.state, isModelLoading: container.dictation.isModelLoading))
                    .font(EkkoType.footnote)
                    .foregroundStyle(EkkoColor.inkSoft)
                Spacer(minLength: 0)
                if container.dictation.state.isListening {
                    LevelBars(
                        levels: container.audio.levelHistory,
                        barCount: 16,
                        maxHeight: 14,
                        tint: EkkoColor.live
                    )
                }
            }

            if container.dictation.isModelLoading {
                ModelLoadingNote(progress: container.dictation.modelLoadProgress)
            }
        }
        .onAppear { isFocused = true }
        .onChange(of: container.dictation.state) { _, newState in
            // The first thing a new user sees working: flash the box green when text lands.
            guard newState == .inserting, !reduceMotion else { return }
            celebrate = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 700_000_000)
                celebrate = false
            }
        }
    }
}

/// The same click-to-dictate affordance Ekko shows beside text fields in other apps, built into
/// the practice box (Ekko does not float its field mic over its own windows).
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
                    .fill(state.isListening ? EkkoColor.live : (isHovering ? EkkoColor.accent.opacity(0.14) : EkkoColor.surfaceMuted))
                Circle()
                    .strokeBorder(state.isListening ? Color.clear : EkkoColor.hairlineStrong, lineWidth: 1)
                if state == .preparing || state == .transcribing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: state.isListening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(state.isListening ? Color.white : (isHovering ? EkkoColor.accent : EkkoColor.inkSoft))
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
        VStack(alignment: .leading, spacing: EkkoSpacing.xs) {
            Text(title)
                .font(EkkoType.stepTitle)
                .foregroundStyle(EkkoColor.ink)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(EkkoType.footnote)
                .foregroundStyle(EkkoColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

import SwiftUI

/// Four-step first run: welcome, permissions, model, try it.
@MainActor
struct OnboardingView: View {
    let container: AppContainer
    let onFinished: () -> Void

    @State private var step: Int

    init(container: AppContainer, initialStep: Int = 0, onFinished: @escaping () -> Void) {
        self.container = container
        self.onFinished = onFinished
        _step = State(initialValue: min(max(initialStep, 0), Self.stepCount - 1))
    }
    @State private var selectedModelID: ModelID?
    @State private var showSkipWarning = false
    @State private var startedDownload = false

    private static let stepCount = 4

    var body: some View {
        VStack(spacing: 0) {
            progress
            ScrollView {
                stepContent
                    .padding(.horizontal, EchoSpacing.xl)
                    .padding(.bottom, EchoSpacing.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            EchoDivider()
            footer
        }
        .frame(width: 640, height: 520)
        .background(EchoColor.page)
        .onAppear {
            if selectedModelID == nil { selectedModelID = recommendation.recommended.id }
        }
        .onChange(of: modelInstalled) { _, installed in
            guard step == 2, startedDownload, installed, let id = selectedModelID else { return }
            startedDownload = false
            container.modelManager.setActive(id)
            advance()
        }
    }

    // MARK: - Chrome

    private var progress: some View {
        HStack(spacing: EchoSpacing.s) {
            ForEach(0..<Self.stepCount, id: \.self) { index in
                Capsule()
                    .fill(index <= step ? EchoColor.accent : EchoColor.hairlineStrong)
                    .frame(height: 3)
            }
        }
        .padding(.horizontal, EchoSpacing.xl)
        .padding(.top, 38)
        .padding(.bottom, EchoSpacing.xl)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Step \(step + 1) of \(Self.stepCount)"))
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0:
            OnboardingWelcomeStep()
        case 1:
            OnboardingPermissionsStep(container: container, showSkipWarning: $showSkipWarning)
        case 2:
            OnboardingModelStep(container: container, selectedModelID: $selectedModelID)
        default:
            OnboardingTryStep(container: container)
        }
    }

    private var footer: some View {
        HStack(spacing: EchoSpacing.m) {
            if step > 0 {
                Button("Back") { step -= 1 }
                    .buttonStyle(.echoQuiet())
                    .accessibilityLabel(Text("Go back a step"))
            }
            Spacer(minLength: 0)

            if step == 1 && !container.permissions.allGranted {
                Button(showSkipWarning ? "Skip anyway" : "Skip for now") {
                    if showSkipWarning { advance() } else { showSkipWarning = true }
                }
                .buttonStyle(.echoQuiet())
                .accessibilityLabel(Text("Skip permissions for now"))
            }

            Button(primaryTitle, action: primaryAction)
                .buttonStyle(.echoPrimary(size: .large))
                .disabled(!primaryEnabled)
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel(Text(primaryTitle))
        }
        .padding(.horizontal, EchoSpacing.xl)
        .padding(.vertical, EchoSpacing.l)
    }

    // MARK: - Flow

    private var recommendation: ModelRecommendation {
        ModelRecommender.recommendation(
            for: container.hardware,
            preferEnglishOnly: container.settings.isEnglish
        )
    }

    private var primaryTitle: String {
        switch step {
        case 0: return "Get started"
        case 1: return "Continue"
        case 2: return modelInstalled ? "Continue" : "Download & continue"
        default: return "Done"
        }
    }

    private var primaryEnabled: Bool {
        switch step {
        case 1: return container.permissions.allGranted
        case 2: return selectedModelID != nil && !modelDownloading
        default: return true
        }
    }

    private var modelInstalled: Bool {
        guard let id = selectedModelID else { return false }
        return container.modelManager.state(for: id).isInstalled
    }

    private var modelDownloading: Bool {
        guard let id = selectedModelID else { return false }
        return container.modelManager.state(for: id).isDownloading
    }

    private func primaryAction() {
        switch step {
        case 2:
            guard let id = selectedModelID else { return }
            if modelInstalled {
                container.modelManager.setActive(id)
                advance()
            } else {
                startedDownload = true
                container.modelManager.download(id)
            }
        case Self.stepCount - 1:
            onFinished()
        default:
            advance()
        }
    }

    private func advance() {
        showSkipWarning = false
        step = min(step + 1, Self.stepCount - 1)
    }
}

import SwiftUI

/// "The model is warming up" — progress plus a plain explanation of why the first load is slow.
struct ModelLoadingNote: View {
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: EchoSpacing.s) {
            HStack(spacing: EchoSpacing.s) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading speech model…")
                    .font(EchoType.captionMedium)
                    .foregroundStyle(EchoColor.ink)
                Spacer(minLength: 0)
                Text("\(Int((progress * 100).rounded()))%")
                    .font(EchoType.caption)
                    .monospacedDigit()
                    .foregroundStyle(EchoColor.inkMuted)
            }
            EchoProgressBar(fraction: progress)
            Text(DictationPresentation.modelLoadingExplanation)
                .font(EchoType.caption)
                .foregroundStyle(EchoColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(EchoSpacing.m)
        .background(EchoColor.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: EchoRadius.control, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Nothing to dictate with yet: point the user at the Models page.
struct ChooseModelCard: View {
    let recommended: ModelDescriptor
    let openModels: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: EchoSpacing.s) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(EchoColor.accent)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("Download a speech model")
                    .font(EchoType.captionMedium)
                    .foregroundStyle(EchoColor.ink)
                Text("We suggest \(recommended.displayName) (\(recommended.sizeLabel)) for this Mac.")
                    .font(EchoType.caption)
                    .foregroundStyle(EchoColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: EchoSpacing.s)
            Button("Choose", action: openModels)
                .buttonStyle(.echoSecondary(size: .small))
                .accessibilityLabel(Text("Choose a speech model"))
        }
        .padding(EchoSpacing.m)
        .background(EchoColor.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: EchoRadius.control, style: .continuous))
    }
}

/// A better model fits this Mac: download it, then switch to it, or dismiss the suggestion.
@MainActor
struct UpgradeModelCard: View {
    let container: AppContainer
    let model: ModelDescriptor

    private var state: ModelInstallState { container.modelManager.state(for: model.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: EchoSpacing.s) {
            HStack(alignment: .top, spacing: EchoSpacing.s) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(EchoColor.accent)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your Mac can run \(model.displayName)")
                        .font(EchoType.captionMedium)
                        .foregroundStyle(EchoColor.ink)
                    Text("It is noticeably more accurate and still quick on the \(container.hardware.chipName).")
                        .font(EchoType.caption)
                        .foregroundStyle(EchoColor.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if case .downloading(let fraction, _, _) = state {
                EchoProgressBar(fraction: fraction)
            }

            HStack(spacing: EchoSpacing.s) {
                primaryAction
                Spacer(minLength: 0)
                Button("Not now") { container.settings.dismissedUpgradeModelID = model.id }
                    .buttonStyle(.echoQuiet(size: .small))
                    .accessibilityLabel(Text("Hide this suggestion"))
            }
        }
        .padding(EchoSpacing.m)
        .background(EchoColor.surface, in: RoundedRectangle(cornerRadius: EchoRadius.control, style: .continuous))
        .echoHairlineBorder(radius: EchoRadius.control)
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch state {
        case .installed:
            Button("Switch to \(model.displayName)") { container.modelManager.setActive(model.id) }
                .buttonStyle(.echoPrimary(size: .small))
                .disabled(container.dictation.state.isActive)
        case .downloading(let fraction, _, _):
            HStack(spacing: EchoSpacing.s) {
                Text("Downloading… \(Int((fraction * 100).rounded()))%")
                    .font(EchoType.caption)
                    .monospacedDigit()
                    .foregroundStyle(EchoColor.inkMuted)
                Button("Cancel") { container.modelManager.cancelDownload(model.id) }
                    .buttonStyle(.echoQuiet(size: .small))
            }
        case .notInstalled, .failed:
            Button("Download (\(model.sizeLabel))") { container.modelManager.download(model.id) }
                .buttonStyle(.echoPrimary(size: .small))
        }
    }
}

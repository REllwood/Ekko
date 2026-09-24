import SwiftUI

/// "The model is warming up" — progress plus a plain explanation of why the first load is slow.
struct ModelLoadingNote: View {
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: EkkoSpacing.s) {
            HStack(spacing: EkkoSpacing.s) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading speech model…")
                    .font(EkkoType.captionMedium)
                    .foregroundStyle(EkkoColor.ink)
                Spacer(minLength: 0)
                Text("\(Int((progress * 100).rounded()))%")
                    .font(EkkoType.caption)
                    .monospacedDigit()
                    .foregroundStyle(EkkoColor.inkMuted)
            }
            EkkoProgressBar(fraction: progress)
            Text(DictationPresentation.modelLoadingExplanation)
                .font(EkkoType.caption)
                .foregroundStyle(EkkoColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(EkkoSpacing.m)
        .background(EkkoColor.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: EkkoRadius.control, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Nothing to dictate with yet: point the user at the Models page.
struct ChooseModelCard: View {
    let recommended: ModelDescriptor
    let openModels: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: EkkoSpacing.s) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(EkkoColor.accent)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("Download a speech model")
                    .font(EkkoType.captionMedium)
                    .foregroundStyle(EkkoColor.ink)
                Text("We suggest \(recommended.displayName) (\(recommended.sizeLabel)) for this Mac.")
                    .font(EkkoType.caption)
                    .foregroundStyle(EkkoColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: EkkoSpacing.s)
            Button("Choose", action: openModels)
                .buttonStyle(.ekkoSecondary(size: .small))
                .accessibilityLabel(Text("Choose a speech model"))
        }
        .padding(EkkoSpacing.m)
        .background(EkkoColor.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: EkkoRadius.control, style: .continuous))
    }
}

/// A better model fits this Mac: download it, then switch to it, or dismiss the suggestion.
@MainActor
struct UpgradeModelCard: View {
    let container: AppContainer
    let model: ModelDescriptor

    private var state: ModelInstallState { container.modelManager.state(for: model.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: EkkoSpacing.s) {
            HStack(alignment: .top, spacing: EkkoSpacing.s) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(EkkoColor.accent)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your Mac can run \(model.displayName)")
                        .font(EkkoType.captionMedium)
                        .foregroundStyle(EkkoColor.ink)
                    Text("It is noticeably more accurate and still quick on the \(container.hardware.chipName).")
                        .font(EkkoType.caption)
                        .foregroundStyle(EkkoColor.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if case .downloading(let fraction, _, _) = state {
                EkkoProgressBar(fraction: fraction)
            }

            HStack(spacing: EkkoSpacing.s) {
                primaryAction
                Spacer(minLength: 0)
                Button("Not now") { container.settings.dismissedUpgradeModelID = model.id }
                    .buttonStyle(.ekkoQuiet(size: .small))
                    .accessibilityLabel(Text("Hide this suggestion"))
            }
        }
        .padding(EkkoSpacing.m)
        .background(EkkoColor.surface, in: RoundedRectangle(cornerRadius: EkkoRadius.control, style: .continuous))
        .ekkoHairlineBorder(radius: EkkoRadius.control)
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch state {
        case .installed:
            Button("Switch to \(model.displayName)") { container.modelManager.setActive(model.id) }
                .buttonStyle(.ekkoPrimary(size: .small))
                .disabled(container.dictation.state.isActive)
        case .downloading(let fraction, _, _):
            HStack(spacing: EkkoSpacing.s) {
                Text("Downloading… \(Int((fraction * 100).rounded()))%")
                    .font(EkkoType.caption)
                    .monospacedDigit()
                    .foregroundStyle(EkkoColor.inkMuted)
                Button("Cancel") { container.modelManager.cancelDownload(model.id) }
                    .buttonStyle(.ekkoQuiet(size: .small))
            }
        case .notInstalled, .failed:
            Button("Download (\(model.sizeLabel))") { container.modelManager.download(model.id) }
                .buttonStyle(.ekkoPrimary(size: .small))
        }
    }
}

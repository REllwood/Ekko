import SwiftUI

@MainActor
struct ModelsPage: View {
    let container: AppContainer

    var body: some View {
        VStack(alignment: .leading, spacing: EchoSpacing.xl) {
            heroCard

            VStack(alignment: .leading, spacing: EchoSpacing.s) {
                SectionHeader(
                    title: "All models",
                    subtitle: "Models are downloaded once and then run entirely on this Mac."
                )
                VStack(spacing: EchoSpacing.m) {
                    ForEach(ModelCatalog.all) { model in
                        ModelCard(
                            container: container,
                            model: model,
                            isRecommended: model.id == recommendation.recommended.id
                        )
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

    /// Download / use / in-use control for the recommended model, so the advice is one click away.
    @ViewBuilder
    private func heroAction(for model: ModelDescriptor) -> some View {
        switch container.modelManager.state(for: model.id) {
        case .installed:
            if container.settings.activeModelID == model.id {
                EchoBadge(text: "In use", tone: .success, icon: "checkmark")
            } else {
                Button("Use this model") { container.modelManager.setActive(model.id) }
                    .buttonStyle(.echoPrimary(size: .small))
                    .disabled(container.dictation.state.isActive)
            }
        case .downloading(let fraction, _, _):
            HStack(spacing: EchoSpacing.s) {
                EchoProgressRing(fraction: fraction)
                Button("Cancel") { container.modelManager.cancelDownload(model.id) }
                    .buttonStyle(.echoQuiet(size: .small))
            }
        case .notInstalled, .failed:
            Button("Download") { container.modelManager.download(model.id) }
                .buttonStyle(.echoPrimary(size: .small))
                .accessibilityLabel(Text("Download \(model.displayName)"))
        }
    }

    private var heroCard: some View {
        let recommendation = recommendation
        return EchoCard(highlighted: true) {
            VStack(alignment: .leading, spacing: EchoSpacing.m) {
                HStack(spacing: EchoSpacing.s) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(EchoColor.accent)
                    Text(container.hardware.summary)
                        .font(EchoType.bodySemibold)
                        .foregroundStyle(EchoColor.ink)
                    EchoBadge(text: recommendation.tier.title, tone: .accent)
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: EchoSpacing.xs) {
                    Text(recommendation.headline)
                        .font(EchoType.cardTitle)
                        .foregroundStyle(EchoColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if !recommendation.rationale.isEmpty {
                        Text(recommendation.rationale)
                            .font(EchoType.footnote)
                            .foregroundStyle(EchoColor.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: EchoSpacing.s) {
                    HStack(spacing: EchoSpacing.s) {
                        EchoChip(icon: "cpu", text: recommendation.recommended.displayName)
                        EchoChip(icon: "internaldrive", text: recommendation.recommended.sizeLabel)
                        Spacer(minLength: 0)
                        heroAction(for: recommendation.recommended)
                    }
                    if !recommendation.alternatives.isEmpty {
                        Text("Also good: \(recommendation.alternatives.prefix(2).map(\.displayName).joined(separator: " · "))")
                            .font(EchoType.caption)
                            .foregroundStyle(EchoColor.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

import SwiftUI

@MainActor
struct ModelsPage: View {
    let container: AppContainer

    var body: some View {
        VStack(alignment: .leading, spacing: EkkoSpacing.xl) {
            heroCard

            VStack(alignment: .leading, spacing: EkkoSpacing.s) {
                SectionHeader(
                    title: "All models",
                    subtitle: "Models are downloaded once and then run entirely on this Mac."
                )
                VStack(spacing: EkkoSpacing.m) {
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
                EkkoBadge(text: "In use", tone: .success, icon: "checkmark")
            } else {
                Button("Use this model") { container.modelManager.setActive(model.id) }
                    .buttonStyle(.ekkoPrimary(size: .small))
                    .disabled(container.dictation.state.isActive)
            }
        case .downloading(let fraction, _, _):
            HStack(spacing: EkkoSpacing.s) {
                EkkoProgressRing(fraction: fraction)
                Button("Cancel") { container.modelManager.cancelDownload(model.id) }
                    .buttonStyle(.ekkoQuiet(size: .small))
            }
        case .notInstalled, .failed:
            Button("Download") { container.modelManager.download(model.id) }
                .buttonStyle(.ekkoPrimary(size: .small))
                .accessibilityLabel(Text("Download \(model.displayName)"))
        }
    }

    private var heroCard: some View {
        let recommendation = recommendation
        return EkkoCard(highlighted: true) {
            VStack(alignment: .leading, spacing: EkkoSpacing.m) {
                HStack(spacing: EkkoSpacing.s) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(EkkoColor.accent)
                    Text(container.hardware.summary)
                        .font(EkkoType.bodySemibold)
                        .foregroundStyle(EkkoColor.ink)
                    EkkoBadge(text: recommendation.tier.title, tone: .accent)
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: EkkoSpacing.xs) {
                    Text(recommendation.headline)
                        .font(EkkoType.cardTitle)
                        .foregroundStyle(EkkoColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if !recommendation.rationale.isEmpty {
                        Text(recommendation.rationale)
                            .font(EkkoType.footnote)
                            .foregroundStyle(EkkoColor.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: EkkoSpacing.s) {
                    HStack(spacing: EkkoSpacing.s) {
                        EkkoChip(icon: "cpu", text: recommendation.recommended.displayName)
                        EkkoChip(icon: "internaldrive", text: recommendation.recommended.sizeLabel)
                        Spacer(minLength: 0)
                        heroAction(for: recommendation.recommended)
                    }
                    if !recommendation.alternatives.isEmpty {
                        Text("Also good: \(recommendation.alternatives.prefix(2).map(\.displayName).joined(separator: " · "))")
                            .font(EkkoType.caption)
                            .foregroundStyle(EkkoColor.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

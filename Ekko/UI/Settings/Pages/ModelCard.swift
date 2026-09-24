import SwiftUI

/// One row in the models list: identity, meters, suitability and the download/select control.
@MainActor
struct ModelCard: View {
    let container: AppContainer
    let model: ModelDescriptor
    var isRecommended = false

    @State private var deleteError: String?

    private var state: ModelInstallState { container.modelManager.state(for: model.id) }
    private var isActive: Bool { container.settings.activeModelID == model.id }

    var body: some View {
        EkkoCard(highlighted: isActive) {
            VStack(alignment: .leading, spacing: EkkoSpacing.m) {
                HStack(alignment: .top, spacing: EkkoSpacing.m) {
                    VStack(alignment: .leading, spacing: EkkoSpacing.xs) {
                        HStack(spacing: EkkoSpacing.s) {
                            Text(model.displayName)
                                .font(EkkoType.bodySemibold)
                                .foregroundStyle(EkkoColor.ink)
                            EkkoBadge(
                                text: model.isEnglishOnly ? "English only" : "100 languages",
                                tone: model.isEnglishOnly ? .neutral : .accent
                            )
                            if isRecommended {
                                EkkoBadge(text: "Recommended", tone: .success, icon: "sparkles")
                            }
                        }
                        Text(model.summary)
                            .font(EkkoType.caption)
                            .foregroundStyle(EkkoColor.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: EkkoSpacing.m)
                    trailingControl
                }

                HStack(spacing: EkkoSpacing.l) {
                    meter(label: "Accuracy", value: model.accuracy, tint: EkkoColor.accent)
                    meter(label: "Speed", value: model.speed, tint: EkkoColor.success)
                    metaLabel(icon: "internaldrive", text: model.sizeLabel)
                    metaLabel(icon: "gauge.with.needle", text: speedEstimate)
                    Spacer(minLength: 0)
                    EkkoBadge(text: suitability.label, tone: suitabilityTone)
                }

                if case .downloading(let fraction, let received, let total) = state {
                    VStack(alignment: .leading, spacing: EkkoSpacing.xs) {
                        EkkoProgressBar(fraction: fraction)
                        Text(downloadLabel(received: received, total: total, fraction: fraction))
                            .font(EkkoType.caption)
                            .foregroundStyle(EkkoColor.inkMuted)
                    }
                }

                if case .failed(let message) = state {
                    Text(message)
                        .font(EkkoType.caption)
                        .foregroundStyle(EkkoColor.live)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let deleteError {
                    Text(deleteError)
                        .font(EkkoType.caption)
                        .foregroundStyle(EkkoColor.live)
                }
            }
        }
    }

    // MARK: - Trailing control

    @ViewBuilder
    private var trailingControl: some View {
        switch state {
        case .notInstalled:
            Button("Download") { container.modelManager.download(model.id) }
                .buttonStyle(.ekkoSecondary())
                .accessibilityLabel(Text("Download \(model.displayName)"))

        case .downloading(let fraction, _, _):
            HStack(spacing: EkkoSpacing.s) {
                EkkoProgressRing(fraction: fraction)
                Button("Cancel") { container.modelManager.cancelDownload(model.id) }
                    .buttonStyle(.ekkoQuiet(size: .small))
                    .accessibilityLabel(Text("Cancel download of \(model.displayName)"))
            }

        case .installed:
            HStack(spacing: EkkoSpacing.s) {
                Button {
                    container.modelManager.setActive(model.id)
                } label: {
                    HStack(spacing: EkkoSpacing.xs) {
                        Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 12))
                        Text(isActive ? "In use" : "Use")
                    }
                }
                .buttonStyle(isActive ? AnyButtonStyle(.ekkoQuiet(tint: EkkoColor.accent)) : AnyButtonStyle(.ekkoSecondary()))
                .disabled(isActive || container.dictation.state.isActive)
                .accessibilityLabel(Text(isActive ? "\(model.displayName) is in use" : "Use \(model.displayName)"))

                Menu {
                    Button("Delete download", role: .destructive) { delete() }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 22)
                .accessibilityLabel(Text("More options for \(model.displayName)"))
            }

        case .failed:
            Button("Try again") { container.modelManager.download(model.id) }
                .buttonStyle(.ekkoSecondary())
                .accessibilityLabel(Text("Retry downloading \(model.displayName)"))
        }
    }

    private func delete() {
        do {
            try container.modelManager.delete(model.id)
            deleteError = nil
        } catch {
            deleteError = error.localizedDescription
            Log.ui.error("Model delete failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Pieces

    private func meter(label: String, value: Int, tint: Color) -> some View {
        HStack(spacing: EkkoSpacing.s) {
            Text(label)
                .font(EkkoType.caption)
                .foregroundStyle(EkkoColor.inkMuted)
            DotMeter(value: value, tint: tint, label: label)
        }
    }

    private func metaLabel(icon: String, text: String) -> some View {
        HStack(spacing: EkkoSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(EkkoColor.inkMuted)
            Text(text)
                .font(EkkoType.caption)
                .foregroundStyle(EkkoColor.inkMuted)
        }
        .accessibilityElement(children: .combine)
    }

    private var suitability: ModelSuitability {
        ModelRecommender.suitability(of: model, on: container.hardware)
    }

    private var suitabilityTone: EkkoBadge.Tone {
        switch suitability {
        case .notRecommended: return .live
        case .slow: return .warning
        case .good: return .neutral
        case .great: return .accent
        case .recommended: return .success
        }
    }

    private var speedEstimate: String {
        let factor = ModelRecommender.estimatedRealtimeFactor(of: model, on: container.hardware)
        guard factor > 0 else { return "Speed unknown" }
        return String(format: "~%.0f× real time", factor)
    }

    private func downloadLabel(received: Int64, total: Int64, fraction: Double) -> String {
        guard total > 0 else { return "Downloading… \(Int((fraction * 100).rounded()))%" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return "\(formatter.string(fromByteCount: received)) of \(formatter.string(fromByteCount: total))"
    }
}

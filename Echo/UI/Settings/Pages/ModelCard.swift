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
        EchoCard(highlighted: isActive) {
            VStack(alignment: .leading, spacing: EchoSpacing.m) {
                HStack(alignment: .top, spacing: EchoSpacing.m) {
                    VStack(alignment: .leading, spacing: EchoSpacing.xs) {
                        HStack(spacing: EchoSpacing.s) {
                            Text(model.displayName)
                                .font(EchoType.bodySemibold)
                                .foregroundStyle(EchoColor.ink)
                            EchoBadge(
                                text: model.isEnglishOnly ? "English only" : "100 languages",
                                tone: model.isEnglishOnly ? .neutral : .accent
                            )
                            if isRecommended {
                                EchoBadge(text: "Recommended", tone: .success, icon: "sparkles")
                            }
                        }
                        Text(model.summary)
                            .font(EchoType.caption)
                            .foregroundStyle(EchoColor.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: EchoSpacing.m)
                    trailingControl
                }

                HStack(spacing: EchoSpacing.l) {
                    meter(label: "Accuracy", value: model.accuracy, tint: EchoColor.accent)
                    meter(label: "Speed", value: model.speed, tint: EchoColor.success)
                    metaLabel(icon: "internaldrive", text: model.sizeLabel)
                    metaLabel(icon: "gauge.with.needle", text: speedEstimate)
                    Spacer(minLength: 0)
                    EchoBadge(text: suitability.label, tone: suitabilityTone)
                }

                if case .downloading(let fraction, let received, let total) = state {
                    VStack(alignment: .leading, spacing: EchoSpacing.xs) {
                        EchoProgressBar(fraction: fraction)
                        Text(downloadLabel(received: received, total: total, fraction: fraction))
                            .font(EchoType.caption)
                            .foregroundStyle(EchoColor.inkMuted)
                    }
                }

                if case .failed(let message) = state {
                    Text(message)
                        .font(EchoType.caption)
                        .foregroundStyle(EchoColor.live)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let deleteError {
                    Text(deleteError)
                        .font(EchoType.caption)
                        .foregroundStyle(EchoColor.live)
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
                .buttonStyle(.echoSecondary())
                .accessibilityLabel(Text("Download \(model.displayName)"))

        case .downloading(let fraction, _, _):
            HStack(spacing: EchoSpacing.s) {
                EchoProgressRing(fraction: fraction)
                Button("Cancel") { container.modelManager.cancelDownload(model.id) }
                    .buttonStyle(.echoQuiet(size: .small))
                    .accessibilityLabel(Text("Cancel download of \(model.displayName)"))
            }

        case .installed:
            HStack(spacing: EchoSpacing.s) {
                Button {
                    container.modelManager.setActive(model.id)
                } label: {
                    HStack(spacing: EchoSpacing.xs) {
                        Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 12))
                        Text(isActive ? "In use" : "Use")
                    }
                }
                .buttonStyle(isActive ? AnyButtonStyle(.echoQuiet(tint: EchoColor.accent)) : AnyButtonStyle(.echoSecondary()))
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
                .buttonStyle(.echoSecondary())
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
        HStack(spacing: EchoSpacing.s) {
            Text(label)
                .font(EchoType.caption)
                .foregroundStyle(EchoColor.inkMuted)
            DotMeter(value: value, tint: tint, label: label)
        }
    }

    private func metaLabel(icon: String, text: String) -> some View {
        HStack(spacing: EchoSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(EchoColor.inkMuted)
            Text(text)
                .font(EchoType.caption)
                .foregroundStyle(EchoColor.inkMuted)
        }
        .accessibilityElement(children: .combine)
    }

    private var suitability: ModelSuitability {
        ModelRecommender.suitability(of: model, on: container.hardware)
    }

    private var suitabilityTone: EchoBadge.Tone {
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

import SwiftUI

/// The floating pill: glyph, live level bars, state text with an optional hint, elapsed time and
/// language. The pill hugs its content (between `minPillWidth` and `maxPillWidth`) inside a
/// larger transparent panel, so no message is ever truncated.
@MainActor
struct HUDView: View {
    let container: AppContainer

    static let pillHeight: CGFloat = 56
    static let minPillWidth: CGFloat = 220
    static let maxPillWidth: CGFloat = 380
    /// The panel leaves room around the pill for the widest state and the soft shadow.
    static let panelSize = NSSize(width: 440, height: 96)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var state: DictationState { container.dictation.state }
    private var isModelLoading: Bool { container.dictation.isModelLoading }
    private var title: String { DictationPresentation.title(for: state, isModelLoading: isModelLoading) }
    private var subtitle: String? { DictationPresentation.hudSubtitle(for: state, isModelLoading: isModelLoading) }

    var body: some View {
        HStack(spacing: EchoSpacing.m) {
            glyph
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 3) {
                if state.isListening {
                    LevelBars(
                        levels: container.audio.levelHistory,
                        barCount: 24,
                        barWidth: 2,
                        spacing: 2,
                        maxHeight: 14,
                        minHeight: 2,
                        tint: EchoColor.live,
                        isActive: true
                    )
                }
                Text(title)
                    .font(EchoType.captionMedium)
                    .foregroundStyle(EchoColor.ink)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(EchoColor.inkMuted)
                        .lineLimit(1)
                }
            }
            .fixedSize(horizontal: true, vertical: false)

            if state.isListening {
                Spacer(minLength: EchoSpacing.s)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(DictationPresentation.elapsedString(container.dictation.listeningDuration))
                        .font(EchoType.mono)
                        .monospacedDigit()
                        .foregroundStyle(EchoColor.inkSoft)
                    Text(DictationPresentation.shortLanguageLabel(for: container.settings.languageCode))
                        .font(.system(size: 9.5, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(EchoColor.inkMuted)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(EchoColor.surfaceMuted.opacity(0.8), in: Capsule(style: .continuous))
                }
                .fixedSize()
            }
        }
        .padding(.leading, EchoSpacing.l)
        .padding(.trailing, EchoSpacing.l + 2)
        .frame(minWidth: Self.minPillWidth, maxWidth: Self.maxPillWidth, minHeight: Self.pillHeight, maxHeight: Self.pillHeight)
        .fixedSize(horizontal: true, vertical: false)
        .echoGlassBackground(in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(EchoColor.hairline, lineWidth: 1))
        .echoFloatingShadow()
        .scaleEffect(reduceMotion ? 1 : (appeared ? 1 : 0.94))
        .opacity(appeared ? 1 : 0)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85), value: title)
        .onAppear {
            withAnimation(reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.32, dampingFraction: 0.82)) {
                appeared = true
            }
        }
        .frame(width: Self.panelSize.width, height: Self.panelSize.height)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Echo — \(title)" + (subtitle.map { ". \($0)" } ?? "")))
    }

    @ViewBuilder
    private var glyph: some View {
        switch state {
        case .transcribing, .preparing:
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
        default:
            Image(systemName: DictationPresentation.glyph(for: state))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(DictationPresentation.tint(for: state))
                .accessibilityHidden(true)
        }
    }
}

import SwiftUI

/// The floating pill: glyph, live level bars, state text with an optional hint, elapsed time and
/// language. The pill hugs its content (between `minPillWidth` and `maxPillWidth`) inside a
/// larger transparent panel, so no message is ever truncated.
@MainActor
struct HUDView: View {
    let container: AppContainer

    static let pillHeight: CGFloat = 60
    static let minPillWidth: CGFloat = 220
    static let maxPillWidth: CGFloat = 380
    /// The panel leaves room around the pill for the widest state and the soft shadow.
    static let panelSize = NSSize(width: 460, height: 100)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    /// While the pill lingers after a session ends, keep showing how it ended ("Inserted",
    /// "Nothing heard") instead of flipping to "Ready" for the last fraction of a second.
    @State private var lastActiveState: DictationState = .idle

    private var state: DictationState {
        let current = container.dictation.state
        return current == .idle ? lastActiveState : current
    }
    private var isModelLoading: Bool { container.dictation.isModelLoading }
    private var title: String { DictationPresentation.title(for: state, isModelLoading: isModelLoading) }
    private var subtitle: String? { DictationPresentation.hudSubtitle(for: state, isModelLoading: isModelLoading) }

    var body: some View {
        HStack(spacing: EkkoSpacing.m) {
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
                        tint: EkkoColor.live,
                        isActive: true
                    )
                }
                // .primary/.secondary adapt to the glass, which follows whatever app is behind it;
                // fixed Ekko tokens would lose contrast over an app in the other appearance.
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .fixedSize(horizontal: true, vertical: false)

            if state.isListening {
                Spacer(minLength: EkkoSpacing.s)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(DictationPresentation.elapsedString(container.dictation.listeningDuration))
                        .font(.system(size: 13, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(DictationPresentation.shortLanguageLabel(for: container.settings.languageCode))
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.08), in: Capsule(style: .continuous))
                }
                .fixedSize()
            }
        }
        .padding(.leading, EkkoSpacing.l)
        .padding(.trailing, EkkoSpacing.l + 2)
        .frame(minWidth: Self.minPillWidth, maxWidth: Self.maxPillWidth, minHeight: Self.pillHeight, maxHeight: Self.pillHeight)
        .fixedSize(horizontal: true, vertical: false)
        .ekkoGlassBackground(in: Capsule(style: .continuous))
        .ekkoFloatingEdge(Capsule(style: .continuous))
        .ekkoFloatingShadow()
        .scaleEffect(reduceMotion ? 1 : (appeared ? 1 : 0.94))
        .opacity(appeared ? 1 : 0)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85), value: title)
        .onAppear {
            if container.dictation.state != .idle { lastActiveState = container.dictation.state }
            withAnimation(reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.32, dampingFraction: 0.82)) {
                appeared = true
            }
        }
        .onChange(of: container.dictation.state) { _, newState in
            if newState != .idle { lastActiveState = newState }
        }
        .frame(width: Self.panelSize.width, height: Self.panelSize.height)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Ekko — \(title)" + (subtitle.map { ". \($0)" } ?? "")))
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

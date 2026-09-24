import SwiftUI

/// Pointer and dimming state shared by `FieldMicController`, the hosting view and the button.
@Observable
@MainActor
final class FieldMicModel {
    var isHovering = false
    var isPressed = false
    /// Faded back while the user is typing so the mic isn't distracting.
    var isDimmed = false
}

/// The 26 pt mic button. Idle: glass with a mic glyph. Listening: coral with a ring that follows
/// the input level. Busy: a small spinner. Then a tick, or a warning glyph if it failed.
/// Clicks are handled by `FieldMicHostingView`; `onToggle` is also the accessibility action.
@MainActor
struct FieldMicView: View {
    let container: AppContainer
    let model: FieldMicModel
    let onToggle: () -> Void

    static let diameter: CGFloat = 26
    /// Room around the button for the pulse ring and the soft shadow.
    static let margin: CGFloat = 6
    static let panelSize = NSSize(width: diameter + margin * 2, height: diameter + margin * 2)
    static let dimmedOpacity: Double = 0.35

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var state: DictationState { container.dictation.state }
    private var stopsDictation: Bool { container.dictation.isSessionActive }

    var body: some View {
        ZStack {
            if state.isListening {
                FieldMicPulse(audio: container.audio, diameter: Self.diameter, reduceMotion: reduceMotion)
            }
            face
            glyph
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .scaleEffect(model.isPressed && !reduceMotion ? 0.9 : 1)
        .opacity(model.isDimmed ? Self.dimmedOpacity : 1)
        .animation(.easeOut(duration: 0.12), value: model.isPressed)
        .animation(.easeOut(duration: 0.12), value: model.isHovering)
        .animation(.easeOut(duration: 0.2), value: model.isDimmed)
        .animation(.easeOut(duration: 0.15), value: state)
        .frame(width: Self.panelSize.width, height: Self.panelSize.height)
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text(stopsDictation ? "Stop dictating" : "Dictate into this field"))
        .accessibilityHint(Text(helpText))
        .accessibilityAction { onToggle() }
    }

    private var helpText: String {
        if stopsDictation { return "Click to stop dictating" }
        return "Click to dictate · or press \(container.settings.hotkey.displayString)"
    }

    @ViewBuilder
    private var face: some View {
        if state.isListening {
            Circle()
                .fill(EkkoColor.live)
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        } else {
            Circle()
                .fill(model.isHovering ? EkkoColor.accent.opacity(0.14) : Color.clear)
                .ekkoGlassBackground(in: Circle())
                .overlay(
                    Circle().strokeBorder(
                        model.isHovering ? EkkoColor.accent.opacity(0.6) : EkkoColor.hairlineStrong,
                        lineWidth: 1
                    )
                )
                .shadow(color: .black.opacity(0.16), radius: 2, y: 1)
        }
    }

    @ViewBuilder
    private var glyph: some View {
        switch state {
        case .preparing, .transcribing:
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.mini)
        case .inserting:
            symbol("checkmark", color: EkkoColor.success, weight: .bold)
        case .failed:
            symbol(DictationPresentation.glyph(for: state), color: EkkoColor.warning)
        case .listening:
            // Hovering a live mic previews what a click does.
            symbol(model.isHovering ? "stop.fill" : "mic.fill", color: .white)
        case .idle:
            symbol("mic.fill", color: model.isHovering ? EkkoColor.accent : EkkoColor.inkSoft)
        }
    }

    private func symbol(_ name: String, color: Color, weight: Font.Weight = .semibold) -> some View {
        Image(systemName: name)
            .font(.system(size: 12, weight: weight))
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}

/// Soft coral ring behind the live button. Its own view so only it re-renders with the level.
private struct FieldMicPulse: View {
    let audio: AudioCaptureService
    let diameter: CGFloat
    let reduceMotion: Bool

    var body: some View {
        let level = CGFloat(min(max(audio.level, 0), 1))
        Circle()
            .fill(EkkoColor.live.opacity(reduceMotion ? 0.22 : 0.16 + 0.2 * Double(level)))
            .frame(width: diameter, height: diameter)
            // Tops out at 1.4 × 26 pt, which still fits inside the panel's margin.
            .scaleEffect(reduceMotion ? 1.18 : 1.08 + 0.32 * level)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: level)
            .accessibilityHidden(true)
    }
}

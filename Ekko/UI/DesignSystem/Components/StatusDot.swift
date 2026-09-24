import SwiftUI

/// A small filled circle used for permission and dictation status.
struct StatusDot: View {
    enum State {
        case ok
        case warning
        case error
        case idle
        case live

        var color: Color {
            switch self {
            case .ok: return EkkoColor.success
            case .warning: return EkkoColor.warning
            case .error: return EkkoColor.danger
            case .idle: return EkkoColor.inkMuted
            case .live: return EkkoColor.live
            }
        }

        var label: String {
            switch self {
            case .ok: return "Granted"
            case .warning: return "Needs attention"
            case .error: return "Not granted"
            case .idle: return "Idle"
            case .live: return "Listening"
            }
        }
    }

    let state: State
    var size: CGFloat = 8
    var pulses = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @SwiftUI.State private var pulse = false

    var body: some View {
        Circle()
            .fill(state.color)
            .frame(width: size, height: size)
            .overlay {
                if pulses && !reduceMotion {
                    Circle()
                        .stroke(state.color.opacity(0.45), lineWidth: 1.5)
                        .scaleEffect(pulse ? 2.1 : 1)
                        .opacity(pulse ? 0 : 1)
                }
            }
            .onAppear {
                guard pulses, !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(state.label))
    }
}

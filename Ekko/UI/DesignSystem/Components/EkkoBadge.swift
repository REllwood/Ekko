import SwiftUI

/// Small capsule label. Tinted fill at low opacity, never a shadow.
struct EkkoBadge: View {
    enum Tone {
        case neutral
        case accent
        case success
        case warning
        case live

        var color: Color {
            switch self {
            case .neutral: return EkkoColor.inkMuted
            case .accent: return EkkoColor.accent
            case .success: return EkkoColor.success
            case .warning: return EkkoColor.warning
            case .live: return EkkoColor.live
            }
        }
    }

    let text: String
    var tone: Tone = .neutral
    var icon: String?

    var body: some View {
        HStack(spacing: EkkoSpacing.xs) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
            }
            Text(text)
                .font(EkkoType.captionMedium)
        }
        .foregroundStyle(tone.color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tone.color.opacity(0.12), in: Capsule(style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(text))
    }
}

/// A tappable chip used in the menu-bar popover (model, language).
struct EkkoChip: View {
    let icon: String
    let text: String
    var action: (() -> Void)?

    @State private var isHovering = false

    var body: some View {
        Group {
            if let action {
                Button(action: action) { label }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(text))
            } else {
                label
            }
        }
        .onHover { isHovering = $0 }
    }

    private var label: some View {
        HStack(spacing: EkkoSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(EkkoColor.inkMuted)
            Text(text)
                .font(EkkoType.caption)
                .foregroundStyle(EkkoColor.inkSoft)
                .lineLimit(1)
        }
        .padding(.horizontal, EkkoSpacing.s)
        .padding(.vertical, 4)
        .background(
            isHovering && action != nil ? EkkoColor.surfaceMuted : EkkoColor.surfaceMuted.opacity(0.6),
            in: Capsule(style: .continuous)
        )
        .overlay(Capsule(style: .continuous).strokeBorder(EkkoColor.hairline, lineWidth: 1))
        .contentShape(Capsule(style: .continuous))
    }
}

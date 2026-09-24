import SwiftUI

/// Filled accent button. The one loud control on a screen.
struct EkkoPrimaryButtonStyle: ButtonStyle {
    var fullWidth = false
    var controlSize: EkkoControlScale = .regular
    var tint: Color = EkkoColor.accent

    func makeBody(configuration: Configuration) -> some View {
        EkkoButtonChrome(
            configuration: configuration,
            fullWidth: fullWidth,
            scale: controlSize,
            fill: tint,
            pressedFill: tint.opacity(0.82),
            hoverFill: tint.opacity(0.9),
            foreground: .white,
            border: nil
        )
    }
}

/// Hairline-bordered button on the surface colour.
struct EkkoSecondaryButtonStyle: ButtonStyle {
    var fullWidth = false
    var controlSize: EkkoControlScale = .regular

    func makeBody(configuration: Configuration) -> some View {
        EkkoButtonChrome(
            configuration: configuration,
            fullWidth: fullWidth,
            scale: controlSize,
            fill: EkkoColor.surface,
            pressedFill: EkkoColor.hairline,
            hoverFill: EkkoColor.surfaceMuted,
            foreground: EkkoColor.ink,
            border: EkkoColor.hairlineStrong
        )
    }
}

/// Borderless text button; fills with `surfaceMuted` on hover.
struct EkkoQuietButtonStyle: ButtonStyle {
    var fullWidth = false
    var controlSize: EkkoControlScale = .regular
    var tint: Color = EkkoColor.inkSoft

    func makeBody(configuration: Configuration) -> some View {
        EkkoButtonChrome(
            configuration: configuration,
            fullWidth: fullWidth,
            scale: controlSize,
            fill: .clear,
            pressedFill: EkkoColor.hairline,
            hoverFill: EkkoColor.surfaceMuted,
            foreground: tint,
            border: nil
        )
    }
}

enum EkkoControlScale {
    case small
    case regular
    case large

    var font: Font {
        switch self {
        case .small: return EkkoType.captionMedium
        case .regular: return EkkoType.bodyMedium
        case .large: return Font.system(size: 15, weight: .semibold)
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .small: return 8
        case .regular: return 12
        case .large: return 16
        }
    }

    var height: CGFloat {
        switch self {
        case .small: return 22
        case .regular: return 28
        case .large: return 38
        }
    }
}

private struct EkkoButtonChrome: View {
    let configuration: ButtonStyle.Configuration
    let fullWidth: Bool
    let scale: EkkoControlScale
    let fill: Color
    let pressedFill: Color
    let hoverFill: Color
    let foreground: Color
    let border: Color?

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(scale.font)
            .foregroundStyle(foreground.opacity(isEnabled ? 1 : 0.4))
            .padding(.horizontal, scale.horizontalPadding)
            .frame(height: scale.height)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(background, in: RoundedRectangle(cornerRadius: EkkoRadius.control, style: .continuous))
            .overlay {
                if let border {
                    RoundedRectangle(cornerRadius: EkkoRadius.control, style: .continuous)
                        .strokeBorder(border.opacity(isEnabled ? 1 : 0.5), lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: EkkoRadius.control, style: .continuous))
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }

    private var background: Color {
        guard isEnabled else { return fill.opacity(fill == .clear ? 0 : 0.35) }
        if configuration.isPressed { return pressedFill }
        if isHovering { return hoverFill }
        return fill
    }
}

extension ButtonStyle where Self == EkkoPrimaryButtonStyle {
    static var ekkoPrimary: EkkoPrimaryButtonStyle { EkkoPrimaryButtonStyle() }
    static func ekkoPrimary(
        fullWidth: Bool = false,
        size: EkkoControlScale = .regular,
        tint: Color = EkkoColor.accent
    ) -> EkkoPrimaryButtonStyle {
        EkkoPrimaryButtonStyle(fullWidth: fullWidth, controlSize: size, tint: tint)
    }
}

extension ButtonStyle where Self == EkkoSecondaryButtonStyle {
    static var ekkoSecondary: EkkoSecondaryButtonStyle { EkkoSecondaryButtonStyle() }
    static func ekkoSecondary(fullWidth: Bool = false, size: EkkoControlScale = .regular) -> EkkoSecondaryButtonStyle {
        EkkoSecondaryButtonStyle(fullWidth: fullWidth, controlSize: size)
    }
}

extension ButtonStyle where Self == EkkoQuietButtonStyle {
    static var ekkoQuiet: EkkoQuietButtonStyle { EkkoQuietButtonStyle() }
    static func ekkoQuiet(size: EkkoControlScale = .regular, tint: Color = EkkoColor.inkSoft) -> EkkoQuietButtonStyle {
        EkkoQuietButtonStyle(controlSize: size, tint: tint)
    }
}

/// Type-erased button style so one `Button` can switch between two Ekko styles.
struct AnyButtonStyle: ButtonStyle {
    private let makeBodyClosure: (Configuration) -> AnyView

    init<S: ButtonStyle>(_ style: S) {
        makeBodyClosure = { configuration in
            AnyView(style.makeBody(configuration: configuration))
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        makeBodyClosure(configuration)
    }
}

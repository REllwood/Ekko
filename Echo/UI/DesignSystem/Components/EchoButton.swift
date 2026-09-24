import SwiftUI

/// Filled accent button. The one loud control on a screen.
struct EchoPrimaryButtonStyle: ButtonStyle {
    var fullWidth = false
    var controlSize: EchoControlScale = .regular
    var tint: Color = EchoColor.accent

    func makeBody(configuration: Configuration) -> some View {
        EchoButtonChrome(
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
struct EchoSecondaryButtonStyle: ButtonStyle {
    var fullWidth = false
    var controlSize: EchoControlScale = .regular

    func makeBody(configuration: Configuration) -> some View {
        EchoButtonChrome(
            configuration: configuration,
            fullWidth: fullWidth,
            scale: controlSize,
            fill: EchoColor.surface,
            pressedFill: EchoColor.hairline,
            hoverFill: EchoColor.surfaceMuted,
            foreground: EchoColor.ink,
            border: EchoColor.hairlineStrong
        )
    }
}

/// Borderless text button; fills with `surfaceMuted` on hover.
struct EchoQuietButtonStyle: ButtonStyle {
    var fullWidth = false
    var controlSize: EchoControlScale = .regular
    var tint: Color = EchoColor.inkSoft

    func makeBody(configuration: Configuration) -> some View {
        EchoButtonChrome(
            configuration: configuration,
            fullWidth: fullWidth,
            scale: controlSize,
            fill: .clear,
            pressedFill: EchoColor.hairline,
            hoverFill: EchoColor.surfaceMuted,
            foreground: tint,
            border: nil
        )
    }
}

enum EchoControlScale {
    case small
    case regular
    case large

    var font: Font {
        switch self {
        case .small: return EchoType.captionMedium
        case .regular: return EchoType.bodyMedium
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

private struct EchoButtonChrome: View {
    let configuration: ButtonStyle.Configuration
    let fullWidth: Bool
    let scale: EchoControlScale
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
            .background(background, in: RoundedRectangle(cornerRadius: EchoRadius.control, style: .continuous))
            .overlay {
                if let border {
                    RoundedRectangle(cornerRadius: EchoRadius.control, style: .continuous)
                        .strokeBorder(border.opacity(isEnabled ? 1 : 0.5), lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: EchoRadius.control, style: .continuous))
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

extension ButtonStyle where Self == EchoPrimaryButtonStyle {
    static var echoPrimary: EchoPrimaryButtonStyle { EchoPrimaryButtonStyle() }
    static func echoPrimary(
        fullWidth: Bool = false,
        size: EchoControlScale = .regular,
        tint: Color = EchoColor.accent
    ) -> EchoPrimaryButtonStyle {
        EchoPrimaryButtonStyle(fullWidth: fullWidth, controlSize: size, tint: tint)
    }
}

extension ButtonStyle where Self == EchoSecondaryButtonStyle {
    static var echoSecondary: EchoSecondaryButtonStyle { EchoSecondaryButtonStyle() }
    static func echoSecondary(fullWidth: Bool = false, size: EchoControlScale = .regular) -> EchoSecondaryButtonStyle {
        EchoSecondaryButtonStyle(fullWidth: fullWidth, controlSize: size)
    }
}

extension ButtonStyle where Self == EchoQuietButtonStyle {
    static var echoQuiet: EchoQuietButtonStyle { EchoQuietButtonStyle() }
    static func echoQuiet(size: EchoControlScale = .regular, tint: Color = EchoColor.inkSoft) -> EchoQuietButtonStyle {
        EchoQuietButtonStyle(controlSize: size, tint: tint)
    }
}

/// Type-erased button style so one `Button` can switch between two Echo styles.
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

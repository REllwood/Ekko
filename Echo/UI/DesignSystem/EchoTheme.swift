import AppKit
import SwiftUI

/// Design tokens for Echo. Every colour carries an explicit dark value so dark mode is a
/// designed palette rather than an inversion. AppKit chrome and SwiftUI views share the same
/// dynamic `NSColor`s.
enum EchoColor {

    // MARK: - Surfaces

    static let pageNS = dynamic(light: 0xF7F7F2, dark: 0x171716)
    static let surfaceNS = dynamic(light: 0xFFFFFF, dark: 0x212120)
    static let surfaceMutedNS = dynamic(light: 0xEFEFEA, dark: 0x2A2A28)
    static let hairlineNS = dynamic(light: 0xE3E3E3, dark: 0x33332F)
    static let hairlineStrongNS = dynamic(light: 0xD5D5D2, dark: 0x3D3D39)

    // MARK: - Text

    static let inkNS = dynamic(light: 0x292929, dark: 0xF2F1EE)
    static let inkSoftNS = dynamic(light: 0x454745, dark: 0xC9C7C1)
    static let inkMutedNS = dynamic(light: 0x72726E, dark: 0x8F8D87)

    // MARK: - Semantic

    static let accentNS = dynamic(light: 0x4B4ACF, dark: 0x7C7BFF)
    static let liveNS = dynamic(light: 0xE5484D, dark: 0xE5484D)
    static let successNS = dynamic(light: 0x2E9E6B, dark: 0x3FBE85)
    static let warningNS = dynamic(light: 0xD68A0C, dark: 0xE8A72B)

    // MARK: - SwiftUI

    static let page = Color(nsColor: pageNS)
    static let surface = Color(nsColor: surfaceNS)
    static let surfaceMuted = Color(nsColor: surfaceMutedNS)
    static let hairline = Color(nsColor: hairlineNS)
    static let hairlineStrong = Color(nsColor: hairlineStrongNS)
    static let ink = Color(nsColor: inkNS)
    static let inkSoft = Color(nsColor: inkSoftNS)
    static let inkMuted = Color(nsColor: inkMutedNS)
    static let accent = Color(nsColor: accentNS)
    static let live = Color(nsColor: liveNS)
    static let success = Color(nsColor: successNS)
    static let warning = Color(nsColor: warningNS)

    // MARK: - Helpers

    static func solid(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return solid(isDark ? dark : light)
        }
    }
}

/// 8-pt spacing grid.
enum EchoSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    /// Padding inside an `EchoCard`.
    static let card: CGFloat = 16
    /// Padding around a settings page.
    static let page: CGFloat = 26
}

enum EchoRadius {
    static let control: CGFloat = 8
    static let card: CGFloat = 12
    static let hud: CGFloat = 18
}

/// Type scale. System font throughout; `.serif` is reserved for the onboarding hero title.
enum EchoType {
    static let pageTitle = Font.title2.weight(.semibold)
    static let cardTitle = Font.title3.weight(.semibold)
    static let heading = Font.system(size: 14, weight: .semibold)
    static let body = Font.system(size: 13)
    static let bodyMedium = Font.system(size: 13, weight: .medium)
    static let bodySemibold = Font.system(size: 13, weight: .semibold)
    static let caption = Font.system(size: 11)
    static let captionMedium = Font.system(size: 11, weight: .medium)
    static let footnote = Font.system(size: 12)
    static let mono = Font.system(size: 12, design: .monospaced)
    /// Onboarding hero only.
    static let hero = Font.system(size: 30, weight: .semibold, design: .serif)
    static let heroSub = Font.system(size: 14)
}

extension View {
    /// Soft shadow used only by floating surfaces (HUD, popover).
    func echoFloatingShadow() -> some View {
        shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: 8)
    }

    /// 1 px hairline border on a rounded rect.
    func echoHairlineBorder(radius: CGFloat, color: Color = EchoColor.hairline) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(color, lineWidth: 1)
        )
    }
}

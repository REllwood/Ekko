import AppKit
import SwiftUI

/// Design tokens for Ekko. Every colour carries an explicit dark value so dark mode is a
/// designed palette rather than an inversion. AppKit chrome and SwiftUI views share the same
/// dynamic `NSColor`s.
enum EkkoColor {

    // MARK: - Surfaces

    static let pageNS = dynamic(light: 0xF7F7F2, dark: 0x171716)
    static let surfaceNS = dynamic(light: 0xFFFFFF, dark: 0x232322)
    static let surfaceMutedNS = dynamic(light: 0xEFEFEA, dark: 0x2A2A28)
    /// Selected sidebar row and similar "you are here" fills.
    static let selectionNS = dynamic(light: 0xE9E8E1, dark: 0x2E2E2C)
    /// Warm hairlines, so borders sit on the paper instead of looking cool grey.
    static let hairlineNS = dynamic(light: 0xE4E3DC, dark: 0x363632)
    static let hairlineStrongNS = dynamic(light: 0xD3D2CA, dark: 0x42423D)

    // MARK: - Text

    static let inkNS = dynamic(light: 0x292929, dark: 0xF2F1EE)
    static let inkSoftNS = dynamic(light: 0x454745, dark: 0xC9C7C1)
    /// ≥ 4.5:1 on page, surface and surfaceMuted in both appearances.
    static let inkMutedNS = dynamic(light: 0x686864, dark: 0x9C9A94)

    // MARK: - Semantic
    //
    // Saturated colours are for dots, icons and fills. Text in a state colour uses the matching
    // `…Text` shade, which keeps AA contrast on the surface and on the colour's own 12% tint.

    static let accentNS = dynamic(light: 0x4B4ACF, dark: 0x7C7BFF)
    /// Filled accent buttons: white text stays ≥ 4.5:1 (the dark accent is too light for that).
    static let accentFillNS = dynamic(light: 0x4B4ACF, dark: 0x5E5CE6)
    static let accentTextNS = dynamic(light: 0x4543C4, dark: 0xA09FFF)
    /// Recording / live. Only ever means "Ekko is listening".
    static let liveNS = dynamic(light: 0xE5484D, dark: 0xE5484D)
    /// Errors and "not granted", kept apart from `live` so red never means two things.
    static let dangerNS = dynamic(light: 0xD93A3F, dark: 0xFF6166)
    static let dangerTextNS = dynamic(light: 0xC4282E, dark: 0xFF7A7E)
    static let successNS = dynamic(light: 0x2E9E6B, dark: 0x3FBE85)
    static let successTextNS = dynamic(light: 0x1F7A50, dark: 0x5AD19B)
    static let warningNS = dynamic(light: 0xD68A0C, dark: 0xE8A72B)
    static let warningTextNS = dynamic(light: 0x9A5B00, dark: 0xF0B94D)

    // MARK: - SwiftUI

    static let page = Color(nsColor: pageNS)
    static let surface = Color(nsColor: surfaceNS)
    static let surfaceMuted = Color(nsColor: surfaceMutedNS)
    static let selection = Color(nsColor: selectionNS)
    static let hairline = Color(nsColor: hairlineNS)
    static let hairlineStrong = Color(nsColor: hairlineStrongNS)
    static let ink = Color(nsColor: inkNS)
    static let inkSoft = Color(nsColor: inkSoftNS)
    static let inkMuted = Color(nsColor: inkMutedNS)
    static let accent = Color(nsColor: accentNS)
    static let accentFill = Color(nsColor: accentFillNS)
    static let accentText = Color(nsColor: accentTextNS)
    static let live = Color(nsColor: liveNS)
    static let danger = Color(nsColor: dangerNS)
    static let dangerText = Color(nsColor: dangerTextNS)
    static let success = Color(nsColor: successNS)
    static let successText = Color(nsColor: successTextNS)
    static let warning = Color(nsColor: warningNS)
    static let warningText = Color(nsColor: warningTextNS)

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
enum EkkoSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    /// Padding inside an `EkkoCard`.
    static let card: CGFloat = 16
    /// Padding around a settings page.
    static let page: CGFloat = 26
    /// Gap between sections on a page.
    static let section: CGFloat = 28
}

enum EkkoRadius {
    static let control: CGFloat = 8
    /// Small cards inside the popover.
    static let notice: CGFloat = 10
    static let card: CGFloat = 12
    static let hud: CGFloat = 18
}

/// Type scale. System font throughout; `.serif` is reserved for the onboarding hero title.
enum EkkoType {
    /// Settings page titles (use with `.tracking(-0.3)`).
    static let pageTitle = Font.system(size: 22, weight: .semibold)
    static let pageSubtitle = Font.system(size: 13)
    /// Onboarding step titles: the serif voice of the welcome screen, one size down.
    static let stepTitle = Font.system(size: 24, weight: .semibold, design: .serif)
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
    func ekkoFloatingShadow() -> some View {
        shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: 8)
    }

    /// Hairline for floating glass surfaces. On macOS 26 the glass draws its own edge, and a fixed
    /// colour would look like a sticker over apps in the other appearance, so none is added there.
    @ViewBuilder
    func ekkoFloatingEdge<S: InsettableShape>(_ shape: S) -> some View {
        if #available(macOS 26.0, *) {
            self
        } else {
            overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        }
    }

    /// 1 px hairline border on a rounded rect.
    func ekkoHairlineBorder(radius: CGFloat, color: Color = EkkoColor.hairline) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(color, lineWidth: 1)
        )
    }
}

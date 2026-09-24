import SwiftUI

/// Liquid Glass on macOS 26, a material everywhere else. Used by the HUD pill and popover chrome.
struct GlassBackground<S: Shape>: ViewModifier {
    let shape: S
    var fallback: Material = .ultraThinMaterial

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(fallback, in: shape)
        }
    }
}

extension View {
    func ekkoGlassBackground<S: Shape>(in shape: S, fallback: Material = .ultraThinMaterial) -> some View {
        modifier(GlassBackground(shape: shape, fallback: fallback))
    }
}

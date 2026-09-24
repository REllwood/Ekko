import SwiftUI

/// A surface panel: 1 px hairline instead of a shadow, 12 pt radius, 16 pt padding.
struct EkkoCard<Content: View>: View {
    private let padding: CGFloat
    private let highlighted: Bool
    private let content: Content

    init(padding: CGFloat = EkkoSpacing.card, highlighted: Bool = false, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.highlighted = highlighted
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(EkkoColor.surface, in: RoundedRectangle(cornerRadius: EkkoRadius.card, style: .continuous))
            .ekkoHairlineBorder(
                radius: EkkoRadius.card,
                color: highlighted ? EkkoColor.accent.opacity(0.55) : EkkoColor.hairline
            )
    }
}

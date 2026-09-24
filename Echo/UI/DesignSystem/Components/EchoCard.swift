import SwiftUI

/// A surface panel: 1 px hairline instead of a shadow, 12 pt radius, 16 pt padding.
struct EchoCard<Content: View>: View {
    private let padding: CGFloat
    private let highlighted: Bool
    private let content: Content

    init(padding: CGFloat = EchoSpacing.card, highlighted: Bool = false, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.highlighted = highlighted
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(EchoColor.surface, in: RoundedRectangle(cornerRadius: EchoRadius.card, style: .continuous))
            .echoHairlineBorder(
                radius: EchoRadius.card,
                color: highlighted ? EchoColor.accent.opacity(0.55) : EchoColor.hairline
            )
    }
}

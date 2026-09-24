import SwiftUI

/// A small card for tips, warnings and prompts. Sits on `surface` with a hairline like every other
/// card; the colour lives only in the icon badge (and, for blockers, a tinted border), so notices
/// never turn into muddy tinted slabs in dark mode.
struct EkkoNotice<Trailing: View>: View {
    enum Emphasis {
        case normal
        /// Something is blocking Ekko from working: tinted border.
        case strong
    }

    let icon: String
    let tint: Color
    var title: String?
    let message: String
    var emphasis: Emphasis = .normal
    private let trailing: Trailing

    init(
        icon: String,
        tint: Color,
        title: String? = nil,
        message: String,
        emphasis: Emphasis = .normal,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.icon = icon
        self.tint = tint
        self.title = title
        self.message = message
        self.emphasis = emphasis
        self.trailing = trailing()
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: EkkoRadius.notice, style: .continuous) }

    var body: some View {
        HStack(alignment: .center, spacing: EkkoSpacing.m) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.14), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                if let title {
                    Text(title)
                        .font(EkkoType.captionMedium)
                        .foregroundStyle(EkkoColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(message)
                    .font(EkkoType.caption)
                    .foregroundStyle(title == nil ? EkkoColor.inkSoft : EkkoColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: EkkoSpacing.s)
            trailing
        }
        .padding(EkkoSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EkkoColor.surface, in: shape)
        .overlay(shape.strokeBorder(emphasis == .strong ? tint.opacity(0.5) : EkkoColor.hairline, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}

extension EkkoNotice where Trailing == EmptyView {
    init(icon: String, tint: Color, title: String? = nil, message: String, emphasis: Emphasis = .normal) {
        self.init(icon: icon, tint: tint, title: title, message: message, emphasis: emphasis) { EmptyView() }
    }
}

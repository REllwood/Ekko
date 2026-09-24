import SwiftUI

/// Small muted label above a group of rows or cards.
struct SectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: EchoSpacing.xxs) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(EchoColor.inkMuted)
            if let subtitle {
                Text(subtitle)
                    .font(EchoType.caption)
                    .foregroundStyle(EchoColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}

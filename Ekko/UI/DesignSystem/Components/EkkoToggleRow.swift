import SwiftUI

/// Title + optional explanation on the left, a switch on the right.
struct EkkoToggleRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool
    var isEnabled = true

    var body: some View {
        HStack(alignment: .center, spacing: EkkoSpacing.m) {
            VStack(alignment: .leading, spacing: EkkoSpacing.xxs) {
                Text(title)
                    .font(EkkoType.body)
                    .foregroundStyle(isEnabled ? EkkoColor.ink : EkkoColor.inkMuted)
                if let subtitle {
                    Text(subtitle)
                        .font(EkkoType.caption)
                        .foregroundStyle(EkkoColor.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: EkkoSpacing.m)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(EkkoColor.accentFill)
                .disabled(!isEnabled)
                .accessibilityLabel(Text(title))
                .accessibilityHint(Text(subtitle ?? ""))
        }
        .padding(.vertical, EkkoSpacing.xs)
    }
}

/// A row that carries an arbitrary trailing control (picker, button, chip).
struct EkkoSettingRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    private let trailing: Trailing

    init(title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: EkkoSpacing.m) {
            VStack(alignment: .leading, spacing: EkkoSpacing.xxs) {
                Text(title)
                    .font(EkkoType.body)
                    .foregroundStyle(EkkoColor.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(EkkoType.caption)
                        .foregroundStyle(EkkoColor.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: EkkoSpacing.m)
            trailing
        }
        .padding(.vertical, EkkoSpacing.xs)
    }
}

/// Hairline separator between rows inside a card.
struct EkkoDivider: View {
    var body: some View {
        Rectangle()
            .fill(EkkoColor.hairline)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

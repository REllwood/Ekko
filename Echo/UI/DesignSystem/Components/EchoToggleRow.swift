import SwiftUI

/// Title + optional explanation on the left, a switch on the right.
struct EchoToggleRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool
    var isEnabled = true

    var body: some View {
        HStack(alignment: .top, spacing: EchoSpacing.m) {
            VStack(alignment: .leading, spacing: EchoSpacing.xxs) {
                Text(title)
                    .font(EchoType.body)
                    .foregroundStyle(EchoColor.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(EchoType.caption)
                        .foregroundStyle(EchoColor.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: EchoSpacing.m)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!isEnabled)
                .accessibilityLabel(Text(title))
                .accessibilityHint(Text(subtitle ?? ""))
        }
        .padding(.vertical, EchoSpacing.xs)
    }
}

/// A row that carries an arbitrary trailing control (picker, button, chip).
struct EchoSettingRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    private let trailing: Trailing

    init(title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top, spacing: EchoSpacing.m) {
            VStack(alignment: .leading, spacing: EchoSpacing.xxs) {
                Text(title)
                    .font(EchoType.body)
                    .foregroundStyle(EchoColor.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(EchoType.caption)
                        .foregroundStyle(EchoColor.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: EchoSpacing.m)
            trailing
        }
        .padding(.vertical, EchoSpacing.xs)
    }
}

/// Hairline separator between rows inside a card.
struct EchoDivider: View {
    var body: some View {
        Rectangle()
            .fill(EchoColor.hairline)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

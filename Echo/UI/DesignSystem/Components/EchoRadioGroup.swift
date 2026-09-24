import SwiftUI

/// A single selectable option with an explanation. Used for activation mode and insertion method.
struct EchoOptionRow: View {
    let title: String
    let detail: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: EchoSpacing.m) {
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? EchoColor.accent : EchoColor.hairlineStrong, lineWidth: 1.5)
                        .frame(width: 14, height: 14)
                    if isSelected {
                        Circle().fill(EchoColor.accent).frame(width: 7, height: 7)
                    }
                }
                .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(EchoType.body)
                        .foregroundStyle(EchoColor.ink)
                    Text(detail)
                        .font(EchoType.caption)
                        .foregroundStyle(EchoColor.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(EchoSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? EchoColor.accent.opacity(0.07) : (isHovering ? EchoColor.surfaceMuted : Color.clear),
                in: RoundedRectangle(cornerRadius: EchoRadius.control, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: EchoRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text(detail))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Vertical list of `EchoOptionRow`s bound to a selection.
struct EchoRadioGroup<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String
    let detail: (Value) -> String

    var body: some View {
        VStack(spacing: EchoSpacing.xs) {
            ForEach(options, id: \.self) { option in
                EchoOptionRow(
                    title: title(option),
                    detail: detail(option),
                    isSelected: option == selection
                ) {
                    selection = option
                }
            }
        }
    }
}

import SwiftUI

/// A single selectable option with an explanation. Used for activation mode and insertion method.
struct EkkoOptionRow: View {
    let title: String
    let detail: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: EkkoSpacing.m) {
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? EkkoColor.accent : EkkoColor.hairlineStrong, lineWidth: 1.5)
                        .frame(width: 14, height: 14)
                    if isSelected {
                        Circle().fill(EkkoColor.accent).frame(width: 7, height: 7)
                    }
                }
                .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(EkkoType.body)
                        .foregroundStyle(EkkoColor.ink)
                    Text(detail)
                        .font(EkkoType.caption)
                        .foregroundStyle(EkkoColor.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(EkkoSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? EkkoColor.accent.opacity(0.07) : (isHovering ? EkkoColor.surfaceMuted : Color.clear),
                in: RoundedRectangle(cornerRadius: EkkoRadius.control, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: EkkoRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text(detail))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Vertical list of `EkkoOptionRow`s bound to a selection.
struct EkkoRadioGroup<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String
    let detail: (Value) -> String

    var body: some View {
        VStack(spacing: EkkoSpacing.xs) {
            ForEach(options, id: \.self) { option in
                EkkoOptionRow(
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

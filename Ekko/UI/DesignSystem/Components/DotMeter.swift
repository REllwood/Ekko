import SwiftUI

/// A 5-dot rating used for a model's accuracy and speed.
struct DotMeter: View {
    let value: Int
    var total: Int = 5
    var tint: Color = EkkoColor.accent
    var label: String

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index < value ? tint : EkkoColor.hairlineStrong)
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text("\(value) of \(total)"))
    }
}

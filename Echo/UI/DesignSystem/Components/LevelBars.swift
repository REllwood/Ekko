import SwiftUI

/// The waveform used in the HUD and the popover: a fixed number of rounded bars driven by a
/// rolling level history (newest last).
struct LevelBars: View {
    let levels: [Float]
    var barCount: Int = 24
    var barWidth: CGFloat = 2.5
    var spacing: CGFloat = 2
    var maxHeight: CGFloat = 22
    var minHeight: CGFloat = 3
    var tint: Color = EchoColor.live
    var isActive: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: spacing) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(tint.opacity(isActive ? opacity(at: index) : 0.25))
                    .frame(width: barWidth, height: height(at: index))
            }
        }
        .frame(height: maxHeight)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: normalized)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Input level"))
    }

    /// Latest `barCount` samples, padded at the front when history is short.
    private var normalized: [CGFloat] {
        var values = levels.suffix(barCount).map { CGFloat(max(0, min(1, $0))) }
        if values.count < barCount {
            values = Array(repeating: 0, count: barCount - values.count) + values
        }
        return values
    }

    private func height(at index: Int) -> CGFloat {
        guard isActive else { return minHeight }
        let value = normalized[index]
        // Slight centre bias so the waveform reads as a shape rather than a bar chart.
        let centre = CGFloat(barCount - 1) / 2
        let distance = abs(CGFloat(index) - centre) / max(centre, 1)
        let bias = 1 - (distance * 0.25)
        return max(minHeight, min(maxHeight, minHeight + value * bias * (maxHeight - minHeight)))
    }

    private func opacity(at index: Int) -> Double {
        // Older samples fade slightly towards the leading edge.
        0.45 + 0.55 * (Double(index) / Double(max(barCount - 1, 1)))
    }
}

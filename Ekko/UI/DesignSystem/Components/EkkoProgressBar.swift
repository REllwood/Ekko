import SwiftUI

/// Determinate bar, 4 pt tall, accent fill on a muted track.
struct EkkoProgressBar: View {
    /// 0...1
    let fraction: Double
    var tint: Color = EkkoColor.accent
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(EkkoColor.surfaceMuted)
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.2), value: fraction)
        .accessibilityElement()
        .accessibilityLabel(Text("Progress"))
        .accessibilityValue(Text("\(Int((max(0, min(1, fraction)) * 100).rounded())) percent"))
    }
}

/// Compact ring used on model cards while downloading.
struct EkkoProgressRing: View {
    let fraction: Double
    var size: CGFloat = 18
    var lineWidth: CGFloat = 2.5
    var tint: Color = EkkoColor.accent

    var body: some View {
        ZStack {
            Circle()
                .stroke(EkkoColor.hairlineStrong, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, fraction)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.2), value: fraction)
        .accessibilityHidden(true)
    }
}

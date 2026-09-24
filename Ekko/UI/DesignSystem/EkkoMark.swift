import AppKit
import SwiftUI

/// The Ekko logo mark: a geometric lowercase "e" whose opening sends out two sound ripples.
/// Same geometry as `Resources/AppIcon.icon` (authored on its 1024 pt canvas, y down); every
/// consumer maps it into its own rect, so the menu bar, the UI and the app icon always agree.
enum EkkoMarkGeometry {
    static let center = CGPoint(x: 408, y: 512)
    /// Ring centre-line radius, stroke width, and how far short of the crossbar the ring stops.
    static let radius: CGFloat = 168
    static let lineWidth: CGFloat = 92
    static let gapDegrees: CGFloat = 38

    struct Ripple {
        let radius: CGFloat
        let lineWidth: CGFloat
        let halfSpanDegrees: CGFloat
        /// Opacity in the resting logo.
        let restingOpacity: Double
    }

    static let ripples = [
        Ripple(radius: 296, lineWidth: 62, halfSpanDegrees: 34, restingOpacity: 0.8),
        Ripple(radius: 398, lineWidth: 48, halfSpanDegrees: 30, restingOpacity: 0.5),
    ]

    /// Tight bounding box of the stroked mark in source units.
    static let bounds: CGRect = {
        let far = ripples[1]
        let minX = center.x - radius - lineWidth / 2
        let maxX = center.x + far.radius + far.lineWidth / 2
        let capCentreY = center.y - far.radius * sin(far.halfSpanDegrees * .pi / 180)
        let minY = min(center.y - radius - lineWidth / 2, capCentreY - far.lineWidth / 2)
        let maxY = 2 * center.y - minY
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }()

    static var aspectRatio: CGFloat { bounds.width / bounds.height }

    /// Scale that aspect-fits the mark into `rect`.
    static func scale(toFit rect: CGRect) -> CGFloat {
        min(rect.width / bounds.width, rect.height / bounds.height)
    }

    /// Maps source units into `rect` (y down), aspect-fit and centred.
    static func transform(into rect: CGRect) -> CGAffineTransform {
        let s = scale(toFit: rect)
        let dx = rect.midX - bounds.midX * s
        let dy = rect.midY - bounds.midY * s
        return CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: dx, ty: dy)
    }

    /// Centre-line of the "e" (crossbar plus open ring), to be stroked with `lineWidth` and round caps.
    static func letterPath(into rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: center.x - radius, y: center.y))
        path.addLine(to: CGPoint(x: center.x + radius, y: center.y))
        // y down: decreasing angles run anticlockwise on screen, up and over the top.
        path.addArc(
            center: center, radius: radius,
            startAngle: 0, endAngle: -(360 - gapDegrees) * .pi / 180,
            clockwise: true
        )
        var t = transform(into: rect)
        return path.copy(using: &t) ?? path
    }

    /// Centre-line of ripple `index` (0 = near, 1 = far).
    static func ripplePath(_ index: Int, into rect: CGRect) -> CGPath {
        let ripple = ripples[index]
        let half = ripple.halfSpanDegrees * .pi / 180
        let path = CGMutablePath()
        path.addArc(center: center, radius: ripple.radius, startAngle: -half, endAngle: half, clockwise: false)
        var t = transform(into: rect)
        return path.copy(using: &t) ?? path
    }
}

/// One part of the mark as a fillable outline, scaled into whatever rect it is given.
struct EkkoMarkPart: Shape {
    enum Part: Equatable {
        case letter
        case ripple(Int)
    }

    let part: Part

    func path(in rect: CGRect) -> Path {
        let scale = EkkoMarkGeometry.scale(toFit: rect)
        let centreLine: CGPath
        let width: CGFloat
        switch part {
        case .letter:
            centreLine = EkkoMarkGeometry.letterPath(into: rect)
            width = EkkoMarkGeometry.lineWidth
        case .ripple(let index):
            centreLine = EkkoMarkGeometry.ripplePath(index, into: rect)
            width = EkkoMarkGeometry.ripples[index].lineWidth
        }
        return Path(centreLine).strokedPath(StrokeStyle(lineWidth: width * scale, lineCap: .round, lineJoin: .round))
    }
}

/// SwiftUI rendering of the mark. The ripples are separate layers so their opacity animates.
struct EkkoMark: View {
    var tint: Color = EkkoColor.accent
    var rippleOpacities: (Double, Double) = (
        EkkoMarkGeometry.ripples[0].restingOpacity,
        EkkoMarkGeometry.ripples[1].restingOpacity
    )

    var body: some View {
        ZStack {
            EkkoMarkPart(part: .letter).fill(tint)
            EkkoMarkPart(part: .ripple(0)).fill(tint).opacity(rippleOpacities.0)
            EkkoMarkPart(part: .ripple(1)).fill(tint).opacity(rippleOpacities.1)
        }
        .aspectRatio(EkkoMarkGeometry.aspectRatio, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Mark plus the "Ekko" name, for headers. With `animatesIn`, the ripples fade in one after the
/// other when it appears (skipped with Reduce Motion).
struct EkkoWordmark: View {
    var markHeight: CGFloat = 14
    var font: Font = .system(size: 15, weight: .semibold)
    var animatesIn = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var nearShown = false
    @State private var farShown = false

    var body: some View {
        HStack(spacing: markHeight * 0.45) {
            EkkoMark(rippleOpacities: (
                nearShown || !animatesIn ? EkkoMarkGeometry.ripples[0].restingOpacity : 0,
                farShown || !animatesIn ? EkkoMarkGeometry.ripples[1].restingOpacity : 0
            ))
            .frame(height: markHeight)
            .onAppear {
                guard animatesIn, !reduceMotion else { nearShown = true; farShown = true; return }
                withAnimation(.easeOut(duration: 0.18).delay(0.15)) { nearShown = true }
                withAnimation(.easeOut(duration: 0.18).delay(0.33)) { farShown = true }
            }
            Text("Ekko")
                .font(font)
                .foregroundStyle(EkkoColor.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Ekko"))
    }
}

/// The app icon as a SwiftUI image (Liquid Glass on macOS 26, flattened before).
struct EkkoAppIcon: View {
    var size: CGFloat = 64

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

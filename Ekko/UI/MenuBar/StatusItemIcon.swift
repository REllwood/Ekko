import AppKit

/// Template menu-bar images built from the Ekko mark. macOS tints them for the current menu-bar
/// appearance; partial alpha shows as lighter grey, which is how the ripples animate.
enum StatusItemIcon {
    static let size = NSSize(width: 22, height: 18)
    /// Frames in one animation cycle (at 12 fps, a one-second pulse).
    static let frameCount = 12

    static func symbol(_ name: String) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Ekko")?
            .withSymbolConfiguration(config)
            ?? NSImage(size: size)
        image.isTemplate = true
        return image
    }

    /// The resting logo.
    static var idle: NSImage {
        mark(near: 0.85, far: 0.5)
    }

    /// Ripples travel outwards and brighten with the input level while Ekko listens.
    static func listening(frame: Int, level: Float) -> NSImage {
        let phase = Double(frame % frameCount) / Double(frameCount)
        let boost = Double(min(max(level, 0), 1)) * 0.45
        let near = 0.3 + 0.7 * wave(phase) * (0.55 + boost)
        let far = 0.15 + 0.85 * wave(phase - 0.3) * (0.55 + boost)
        return mark(near: min(near + boost * 0.5, 1), far: min(far + boost * 0.3, 1))
    }

    /// A calmer, slower pulse while the model works.
    static func transcribing(frame: Int) -> NSImage {
        let phase = Double(frame % frameCount) / Double(frameCount)
        return mark(near: 0.25 + 0.45 * wave(phase), far: 0.15 + 0.35 * wave(phase - 0.5))
    }

    /// 0…1…0 over one cycle.
    private static func wave(_ phase: Double) -> Double {
        (1 - cos(2 * .pi * phase)) / 2
    }

    private static func mark(near: Double, far: Double) -> NSImage {
        let image = NSImage(size: size, flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let box = rect.insetBy(dx: 1, dy: 2)
            let scale = EkkoMarkGeometry.scale(toFit: box)
            context.setLineCap(.round)
            context.setLineJoin(.round)

            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineWidth(EkkoMarkGeometry.lineWidth * scale)
            context.addPath(EkkoMarkGeometry.letterPath(into: box))
            context.strokePath()

            for (index, ripple) in EkkoMarkGeometry.ripples.enumerated() {
                let alpha = index == 0 ? near : far
                context.setStrokeColor(NSColor.black.withAlphaComponent(alpha).cgColor)
                context.setLineWidth(ripple.lineWidth * scale)
                context.addPath(EkkoMarkGeometry.ripplePath(index, into: box))
                context.strokePath()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Ekko"
        return image
    }
}

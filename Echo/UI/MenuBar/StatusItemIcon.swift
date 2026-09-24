import AppKit

/// Template menu-bar images. All are 18 pt and `isTemplate`, so macOS tints them for the
/// current menu-bar appearance.
enum StatusItemIcon {
    static let size = NSSize(width: 18, height: 18)
    /// Frames in one animation cycle.
    static let frameCount = 12

    static func symbol(_ name: String) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Echo")?
            .withSymbolConfiguration(config)
            ?? NSImage(size: size)
        image.isTemplate = true
        return image
    }

    /// Three bars whose heights travel through a sine cycle — the listening animation.
    static func listening(frame: Int) -> NSImage {
        bars(frame: frame, amplitude: 1.0)
    }

    /// Calmer version of the same shape while the engine runs.
    static func transcribing(frame: Int) -> NSImage {
        bars(frame: frame, amplitude: 0.45)
    }

    private static func bars(frame: Int, amplitude: Double) -> NSImage {
        let phase = Double(frame % frameCount) / Double(frameCount) * 2 * .pi
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            let barWidth: CGFloat = 2.5
            let gap: CGFloat = 3
            let totalWidth = barWidth * 3 + gap * 2
            let startX = rect.midX - totalWidth / 2
            let minHeight: CGFloat = 4
            let maxHeight: CGFloat = 15
            for index in 0..<3 {
                let offset = phase + Double(index) * (2 * .pi / 3)
                let wave = (sin(offset) + 1) / 2
                let height = minHeight + CGFloat(wave * amplitude) * (maxHeight - minHeight)
                let barRect = NSRect(
                    x: startX + CGFloat(index) * (barWidth + gap),
                    y: rect.midY - height / 2,
                    width: barWidth,
                    height: height
                )
                NSBezierPath(roundedRect: barRect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

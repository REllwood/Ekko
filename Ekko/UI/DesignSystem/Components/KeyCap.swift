import SwiftUI

/// One key drawn as a physical cap, with a 2 pt lip so it reads as something you press.
/// Use `KeyCapRow` to render a whole shortcut.
struct KeyCap: View {
    let text: String
    var size: CGFloat = 13

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 6, style: .continuous) }

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(EkkoColor.ink)
            .padding(.horizontal, text.count > 1 ? 8 : 6)
            .frame(minWidth: size + 14, minHeight: size + 12)
            .background(EkkoColor.surface, in: shape)
            .overlay(shape.strokeBorder(EkkoColor.hairlineStrong, lineWidth: 1))
            .background(shape.fill(EkkoColor.hairlineStrong).offset(y: 2))
            .padding(.bottom, 2)
            .accessibilityHidden(true)
    }
}

/// Renders a `Hotkey` as key caps. A modifier on its own is one key ("Right ⌥"), so it is one
/// cap; a combination gets a cap per key ("⌥" "Space").
struct KeyCapRow: View {
    let hotkey: Hotkey
    var size: CGFloat = 13

    var body: some View {
        HStack(spacing: EkkoSpacing.xs) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                KeyCap(text: part, size: size)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Shortcut \(hotkey.displayString)"))
    }

    private var parts: [String] {
        if hotkey.isModifierOnly { return [hotkey.displayString] }
        let raw = hotkey.displayString.split(separator: " ").map(String.init)
        return raw.isEmpty ? ["—"] : raw
    }
}

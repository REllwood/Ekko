import SwiftUI

/// One key drawn as a physical cap. Use `KeyCapRow` to render a whole shortcut.
struct KeyCap: View {
    let text: String
    var size: CGFloat = 13

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(EkkoColor.ink)
            .padding(.horizontal, text.count > 1 ? 8 : 6)
            .frame(minWidth: size + 14, minHeight: size + 12)
            .background(EkkoColor.surface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(EkkoColor.hairlineStrong, lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}

/// Renders a `Hotkey` as a row of key caps, e.g. `Right` `⌥` or `⌥` `Space`.
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
        let raw = hotkey.displayString.split(separator: " ").map(String.init)
        return raw.isEmpty ? ["—"] : raw
    }
}

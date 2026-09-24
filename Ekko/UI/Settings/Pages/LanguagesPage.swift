import SwiftUI

@MainActor
struct LanguagesPage: View {
    let container: AppContainer

    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: EkkoSpacing.l) {
            searchField

            if usesEnglishOnlyModel {
                noticeCard
            }

            if query.isEmpty {
                section(title: "Detection") {
                    row(code: nil, name: "Auto-detect", detail: "Ekko works out the language from what it hears.")
                }
                if !Language.popular.isEmpty {
                    section(title: "Common") {
                        ForEach(Language.popular) { language in
                            row(code: language.code, name: language.englishName, detail: language.nativeName)
                        }
                    }
                }
                section(title: "All languages") {
                    ForEach(Language.all) { language in
                        row(code: language.code, name: language.englishName, detail: language.nativeName)
                    }
                }
            } else {
                section(title: "Results") {
                    if matches.isEmpty {
                        Text("No language matches “\(query)”.")
                            .font(EkkoType.footnote)
                            .foregroundStyle(EkkoColor.inkMuted)
                            .padding(EkkoSpacing.m)
                    } else {
                        ForEach(matches) { language in
                            row(code: language.code, name: language.englishName, detail: language.nativeName)
                        }
                    }
                }
            }
        }
    }

    private var matches: [Language] {
        let needle = query.lowercased()
        return Language.all.filter {
            $0.englishName.lowercased().contains(needle)
                || $0.nativeName.lowercased().contains(needle)
                || $0.code.lowercased() == needle
        }
    }

    private var usesEnglishOnlyModel: Bool {
        guard let id = container.settings.activeModelID,
              let model = ModelCatalog.descriptor(for: id) else { return false }
        return model.isEnglishOnly
    }

    private var searchField: some View {
        HStack(spacing: EkkoSpacing.s) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(EkkoColor.inkMuted)
            TextField("Search languages", text: $query)
                .textFieldStyle(.plain)
                .font(EkkoType.body)
                .accessibilityLabel(Text("Search languages"))
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(EkkoColor.inkMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear search"))
            }
        }
        .padding(.horizontal, EkkoSpacing.m)
        .frame(height: 32)
        .background(EkkoColor.surface, in: RoundedRectangle(cornerRadius: EkkoRadius.control, style: .continuous))
        .ekkoHairlineBorder(radius: EkkoRadius.control)
    }

    private var noticeCard: some View {
        EkkoNotice(
            icon: "info",
            tint: EkkoColor.accent,
            message: "Your current model is English-only, so this choice is ignored until you switch to a multilingual model."
        )
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: EkkoSpacing.s) {
            SectionHeader(title: title)
            EkkoCard(padding: EkkoSpacing.xs) {
                VStack(spacing: 0) { content() }
            }
        }
    }

    private func row(code: String?, name: String, detail: String) -> some View {
        LanguageRow(
            name: name,
            detail: detail,
            isSelected: container.settings.languageCode == code
        ) {
            container.settings.languageCode = code
        }
    }
}

private struct LanguageRow: View {
    let name: String
    let detail: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: EkkoSpacing.m) {
                Text(name)
                    .font(EkkoType.body)
                    .foregroundStyle(EkkoColor.ink)
                Text(detail)
                    .font(EkkoType.caption)
                    .foregroundStyle(EkkoColor.inkMuted)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(EkkoColor.accent)
                }
            }
            .padding(.horizontal, EkkoSpacing.m)
            .frame(height: 32)
            .background(
                isHovering ? EkkoColor.surfaceMuted : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(Text(name))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

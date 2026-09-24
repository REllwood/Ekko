import SwiftUI

/// Sidebar + page content. ⌘1…⌘7 jump between pages for keyboard navigation.
@MainActor
struct SettingsView: View {
    let container: AppContainer
    @Bindable var navigation: SettingsNavigation

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 200)
                .background(EchoColor.page)
            Rectangle()
                .fill(EchoColor.hairline)
                .frame(width: 1)
                .accessibilityHidden(true)
            content
        }
        .frame(minWidth: 720, minHeight: 480)
        .background(EchoColor.page)
        .background(shortcuts)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: EchoSpacing.xs) {
            Text("Echo")
                .font(EchoType.bodySemibold)
                .foregroundStyle(EchoColor.ink)
                .padding(.horizontal, EchoSpacing.m)
                .padding(.top, 34)
                .padding(.bottom, EchoSpacing.s)
                .accessibilityAddTraits(.isHeader)

            ForEach(SettingsPage.allCases) { page in
                SidebarRow(page: page, isSelected: navigation.page == page) {
                    navigation.page = page
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, EchoSpacing.s)
        .padding(.bottom, EchoSpacing.m)
        .accessibilityLabel(Text("Settings sections"))
    }

    /// Invisible buttons that give every page a ⌘-number shortcut.
    private var shortcuts: some View {
        ZStack {
            ForEach(Array(SettingsPage.allCases.enumerated()), id: \.element) { index, page in
                Button("") { navigation.page = page }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: EchoSpacing.xs) {
                Text(navigation.page.title)
                    .font(EchoType.pageTitle)
                    .foregroundStyle(EchoColor.ink)
                Text(navigation.page.subtitle)
                    .font(EchoType.footnote)
                    .foregroundStyle(EchoColor.inkMuted)
            }
            .padding(.horizontal, EchoSpacing.page)
            .padding(.top, 34)
            .padding(.bottom, EchoSpacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)

            ScrollView {
                page
                    .padding(.horizontal, EchoSpacing.page)
                    .padding(.bottom, EchoSpacing.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var page: some View {
        switch navigation.page {
        case .general: GeneralPage(container: container)
        case .dictation: DictationPage(container: container)
        case .models: ModelsPage(container: container)
        case .languages: LanguagesPage(container: container)
        case .shortcut: ShortcutPage(container: container)
        case .permissions: PermissionsPage(container: container)
        case .about: AboutPage(container: container)
        }
    }
}

private struct SidebarRow: View {
    let page: SettingsPage
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: EchoSpacing.s) {
                Image(systemName: page.symbol)
                    .font(.system(size: 12))
                    .frame(width: 16)
                    .foregroundStyle(isSelected ? EchoColor.accent : EchoColor.inkMuted)
                Text(page.title)
                    .font(EchoType.body)
                    .foregroundStyle(isSelected ? EchoColor.ink : EchoColor.inkSoft)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, EchoSpacing.s)
            .frame(height: 30)
            .background(
                isSelected ? EchoColor.surfaceMuted : (isHovering ? EchoColor.surfaceMuted.opacity(0.6) : Color.clear),
                in: RoundedRectangle(cornerRadius: EchoRadius.control, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: EchoRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(Text(page.title))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

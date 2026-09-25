import AppKit
import SwiftUI

@MainActor
struct AboutPage: View {
    let container: AppContainer

    @State private var showLicences = false

    var body: some View {
        VStack(alignment: .leading, spacing: EkkoSpacing.section) {
            EkkoCard {
                HStack(alignment: .top, spacing: EkkoSpacing.l) {
                    EkkoAppIcon(size: 72)

                    VStack(alignment: .leading, spacing: EkkoSpacing.xs) {
                        Text("Ekko")
                            .font(EkkoType.cardTitle)
                            .foregroundStyle(EkkoColor.ink)
                        Text("Version \(Bundle.main.shortVersion)")
                            .font(EkkoType.footnote)
                            .foregroundStyle(EkkoColor.inkMuted)
                        Text("Everything runs on this Mac.")
                            .font(EkkoType.body)
                            .foregroundStyle(EkkoColor.inkSoft)
                            .padding(.top, EkkoSpacing.xs)
                    }
                    Spacer(minLength: 0)
                }
            }

            VStack(alignment: .leading, spacing: EkkoSpacing.s) {
                SectionHeader(title: "This Mac")
                EkkoCard {
                    VStack(alignment: .leading, spacing: EkkoSpacing.xs) {
                        Text(container.hardware.summary)
                            .font(EkkoType.body)
                            .foregroundStyle(EkkoColor.ink)
                        Text("Performance tier: \(container.hardware.performanceTier.title)")
                            .font(EkkoType.caption)
                            .foregroundStyle(EkkoColor.inkMuted)
                    }
                }
            }

            HStack(spacing: EkkoSpacing.s) {
                Text("Speech recognition by WhisperKit")
                    .font(EkkoType.caption)
                    .foregroundStyle(EkkoColor.inkMuted)
                Text("·")
                    .font(EkkoType.caption)
                    .foregroundStyle(EkkoColor.inkMuted)
                Button("Open-source licences") { showLicences = true }
                    .buttonStyle(.ekkoLink(tint: EkkoColor.accentText, font: EkkoType.caption))
                Spacer(minLength: 0)
            }
        }
        .sheet(isPresented: $showLicences) {
            LicencesSheet { showLicences = false }
        }
    }
}

/// The bundled Acknowledgements.txt: WhisperKit's MIT licence, its third-party notices, and credits
/// for the speech models.
private struct LicencesSheet: View {
    let close: () -> Void

    private var text: String {
        guard let url = Bundle.main.url(forResource: "Acknowledgements", withExtension: "txt"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return "Acknowledgements are missing from this build."
        }
        return contents
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Open-source licences")
                    .font(EkkoType.cardTitle)
                    .foregroundStyle(EkkoColor.ink)
                Spacer()
                Button("Done", action: close)
                    .buttonStyle(.ekkoPrimary(size: .small))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(EkkoSpacing.l)
            EkkoDivider()
            ScrollView {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(EkkoColor.inkSoft)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(EkkoSpacing.l)
            }
        }
        .frame(width: 620, height: 460)
        .background(EkkoColor.page)
    }
}

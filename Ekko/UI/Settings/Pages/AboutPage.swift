import AppKit
import SwiftUI

@MainActor
struct AboutPage: View {
    let container: AppContainer

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

            Text("Speech recognition by WhisperKit")
                .font(EkkoType.caption)
                .foregroundStyle(EkkoColor.inkMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

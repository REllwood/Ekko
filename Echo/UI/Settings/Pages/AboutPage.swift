import AppKit
import SwiftUI

@MainActor
struct AboutPage: View {
    let container: AppContainer

    var body: some View {
        VStack(alignment: .leading, spacing: EchoSpacing.l) {
            EchoCard {
                HStack(alignment: .top, spacing: EchoSpacing.l) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 72, height: 72)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: EchoSpacing.xs) {
                        Text("Echo")
                            .font(EchoType.cardTitle)
                            .foregroundStyle(EchoColor.ink)
                        Text("Version \(Bundle.main.shortVersion)")
                            .font(EchoType.footnote)
                            .foregroundStyle(EchoColor.inkMuted)
                        Text("Everything runs on this Mac.")
                            .font(EchoType.body)
                            .foregroundStyle(EchoColor.inkSoft)
                            .padding(.top, EchoSpacing.xs)
                    }
                    Spacer(minLength: 0)
                }
            }

            EchoCard {
                VStack(alignment: .leading, spacing: EchoSpacing.s) {
                    SectionHeader(title: "This Mac")
                    Text(container.hardware.summary)
                        .font(EchoType.body)
                        .foregroundStyle(EchoColor.ink)
                    Text("Performance tier: \(container.hardware.performanceTier.title)")
                        .font(EchoType.caption)
                        .foregroundStyle(EchoColor.inkMuted)
                }
            }

            Text("Speech recognition by WhisperKit")
                .font(EchoType.caption)
                .foregroundStyle(EchoColor.inkMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

import SwiftUI

@MainActor
struct GeneralPage: View {
    let container: AppContainer

    @State private var didClearHistory = false

    var body: some View {
        @Bindable var settings = container.settings

        VStack(alignment: .leading, spacing: EkkoSpacing.section) {
            VStack(alignment: .leading, spacing: EkkoSpacing.s) {
                SectionHeader(title: "Startup & feedback")
                EkkoCard {
                    VStack(spacing: EkkoSpacing.xs) {
                        EkkoToggleRow(
                            title: "Launch Ekko at login",
                            subtitle: "Ekko lives in the menu bar and uses almost nothing when idle.",
                            isOn: $settings.launchAtLogin
                        )
                        EkkoDivider()
                        EkkoToggleRow(
                            title: "Show a mic next to text fields",
                            subtitle: "Click it to dictate into that field, in any app. No keyboard needed.",
                            isOn: $settings.showFieldMic
                        )
                        EkkoDivider()
                        EkkoToggleRow(
                            title: "Show the dictation HUD",
                            subtitle: "A small pill near the bottom of the screen while you speak.",
                            isOn: $settings.showHUD
                        )
                        EkkoDivider()
                        EkkoToggleRow(
                            title: "Play sounds",
                            subtitle: "A short tone when dictation starts and finishes.",
                            isOn: $settings.playSounds
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: EkkoSpacing.s) {
                SectionHeader(title: "Microphone")
                EkkoCard {
                    EkkoSettingRow(
                        title: "Input device",
                        subtitle: inputSubtitle
                    ) {
                        Picker("", selection: $settings.inputDeviceID) {
                            Text("System default").tag(String?.none)
                            ForEach(container.audio.availableInputs) { device in
                                Text(device.name).tag(String?.some(device.id))
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                        .accessibilityLabel(Text("Microphone input device"))
                    }
                }
            }

            VStack(alignment: .leading, spacing: EkkoSpacing.s) {
                SectionHeader(title: "History")
                EkkoCard {
                    VStack(spacing: EkkoSpacing.xs) {
                        EkkoToggleRow(
                            title: "Keep a history of transcriptions",
                            subtitle: "Stored on this Mac only, so you can copy something again later.",
                            isOn: $settings.keepHistory
                        )
                        EkkoDivider()
                        EkkoSettingRow(
                            title: "Clear history",
                            subtitle: historySubtitle
                        ) {
                            Button(didClearHistory ? "Cleared" : "Clear history") {
                                container.dictation.clearHistory()
                                didClearHistory = true
                            }
                            .buttonStyle(.ekkoSecondary())
                            .disabled(container.dictation.history.isEmpty)
                            .accessibilityLabel(Text("Clear transcription history"))
                        }
                    }
                }
            }
        }
        .onAppear {
            container.audio.refreshInputs()
            didClearHistory = false
        }
    }

    private var inputSubtitle: String {
        if container.audio.availableInputs.isEmpty {
            return "No microphones found yet. Ekko will use whatever macOS is using."
        }
        return "Ekko follows your system default unless you pick a specific microphone."
    }

    private var historySubtitle: String {
        let count = container.dictation.history.count
        if count == 0 { return "Nothing recorded yet." }
        return "\(count) transcription\(count == 1 ? "" : "s") kept on this Mac."
    }
}

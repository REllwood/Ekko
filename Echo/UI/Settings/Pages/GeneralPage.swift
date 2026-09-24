import SwiftUI

@MainActor
struct GeneralPage: View {
    let container: AppContainer

    @State private var didClearHistory = false

    var body: some View {
        @Bindable var settings = container.settings

        VStack(alignment: .leading, spacing: EchoSpacing.xl) {
            VStack(alignment: .leading, spacing: EchoSpacing.s) {
                SectionHeader(title: "Startup & feedback")
                EchoCard {
                    VStack(spacing: EchoSpacing.xs) {
                        EchoToggleRow(
                            title: "Launch Echo at login",
                            subtitle: "Echo lives in the menu bar and uses almost nothing when idle.",
                            isOn: $settings.launchAtLogin
                        )
                        EchoDivider()
                        EchoToggleRow(
                            title: "Show a mic next to text fields",
                            subtitle: "Click it to dictate into that field, in any app. No keyboard needed.",
                            isOn: $settings.showFieldMic
                        )
                        EchoDivider()
                        EchoToggleRow(
                            title: "Show the dictation HUD",
                            subtitle: "A small pill near the bottom of the screen while you speak.",
                            isOn: $settings.showHUD
                        )
                        EchoDivider()
                        EchoToggleRow(
                            title: "Play sounds",
                            subtitle: "A short tone when dictation starts and finishes.",
                            isOn: $settings.playSounds
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: EchoSpacing.s) {
                SectionHeader(title: "Microphone")
                EchoCard {
                    EchoSettingRow(
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

            VStack(alignment: .leading, spacing: EchoSpacing.s) {
                SectionHeader(title: "History")
                EchoCard {
                    VStack(spacing: EchoSpacing.xs) {
                        EchoToggleRow(
                            title: "Keep a history of transcriptions",
                            subtitle: "Stored on this Mac only, so you can copy something again later.",
                            isOn: $settings.keepHistory
                        )
                        EchoDivider()
                        EchoSettingRow(
                            title: "Clear history",
                            subtitle: historySubtitle
                        ) {
                            Button(didClearHistory ? "Cleared" : "Clear history") {
                                container.dictation.clearHistory()
                                didClearHistory = true
                            }
                            .buttonStyle(.echoSecondary())
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
            return "No microphones found yet. Echo will use whatever macOS is using."
        }
        return "Echo follows your system default unless you pick a specific microphone."
    }

    private var historySubtitle: String {
        let count = container.dictation.history.count
        if count == 0 { return "Nothing recorded yet." }
        return "\(count) transcription\(count == 1 ? "" : "s") kept on this Mac."
    }
}

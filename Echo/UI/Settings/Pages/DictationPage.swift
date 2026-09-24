import SwiftUI

@MainActor
struct DictationPage: View {
    let container: AppContainer

    /// Spoken commands the formatter understands when voice commands are on.
    private static let voiceCommands = [
        "new line", "new paragraph", "comma", "period", "question mark", "exclamation mark",
    ]

    var body: some View {
        @Bindable var settings = container.settings

        VStack(alignment: .leading, spacing: EchoSpacing.xl) {
            VStack(alignment: .leading, spacing: EchoSpacing.s) {
                SectionHeader(title: "When you press the shortcut")
                EchoCard(padding: EchoSpacing.s) {
                    EchoRadioGroup(
                        selection: $settings.activationMode,
                        options: ActivationMode.allCases,
                        title: \.title,
                        detail: \.detail
                    )
                }
            }

            VStack(alignment: .leading, spacing: EchoSpacing.s) {
                SectionHeader(title: "Text clean-up")
                EchoCard {
                    VStack(spacing: EchoSpacing.xs) {
                        EchoToggleRow(
                            title: "Smart capitalization",
                            subtitle: "Capitalize the first word when you are starting a sentence.",
                            isOn: $settings.smartCapitalization
                        )
                        EchoDivider()
                        EchoToggleRow(
                            title: "Smart spacing",
                            subtitle: "Add a space before the new text when the cursor needs one.",
                            isOn: $settings.smartSpacing
                        )
                        EchoDivider()
                        EchoToggleRow(
                            title: "Voice commands",
                            subtitle: "Say \(Self.voiceCommands.map { "“\($0)”" }.joined(separator: ", ")) and Echo types the punctuation instead of the words.",
                            isOn: $settings.voiceCommandsEnabled
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: EchoSpacing.s) {
                SectionHeader(
                    title: "How text arrives",
                    subtitle: "Automatic is right for almost everyone. Change it only if an app misbehaves."
                )
                EchoCard(padding: EchoSpacing.s) {
                    EchoRadioGroup(
                        selection: $settings.insertionMethod,
                        options: InsertionMethod.allCases,
                        title: \.title,
                        detail: \.detail
                    )
                }
                EchoCard {
                    EchoToggleRow(
                        title: "Restore the clipboard after pasting",
                        subtitle: "Puts back whatever you had copied, a moment after Echo pastes.",
                        isOn: $settings.restoreClipboardAfterPaste,
                        isEnabled: settings.insertionMethod == .auto || settings.insertionMethod == .paste
                    )
                }
            }
        }
    }
}

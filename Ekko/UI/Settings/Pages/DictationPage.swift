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

        VStack(alignment: .leading, spacing: EkkoSpacing.section) {
            VStack(alignment: .leading, spacing: EkkoSpacing.s) {
                SectionHeader(title: "When you press the shortcut")
                EkkoCard(padding: EkkoSpacing.s) {
                    EkkoRadioGroup(
                        selection: $settings.activationMode,
                        options: ActivationMode.allCases,
                        title: \.title,
                        detail: \.detail
                    )
                }
            }

            VStack(alignment: .leading, spacing: EkkoSpacing.s) {
                SectionHeader(title: "Text clean-up")
                EkkoCard {
                    VStack(spacing: EkkoSpacing.xs) {
                        EkkoToggleRow(
                            title: "Smart capitalization",
                            subtitle: "Capitalize the first word when you are starting a sentence.",
                            isOn: $settings.smartCapitalization
                        )
                        EkkoDivider()
                        EkkoToggleRow(
                            title: "Smart spacing",
                            subtitle: "Add a space before the new text when the cursor needs one.",
                            isOn: $settings.smartSpacing
                        )
                        EkkoDivider()
                        EkkoToggleRow(
                            title: "Voice commands",
                            subtitle: "Say \(Self.voiceCommands.map { "“\($0)”" }.joined(separator: ", ")) and Ekko types the punctuation instead of the words.",
                            isOn: $settings.voiceCommandsEnabled
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: EkkoSpacing.s) {
                SectionHeader(
                    title: "How text arrives",
                    subtitle: "Automatic is right for almost everyone. Change it only if an app misbehaves."
                )
                EkkoCard(padding: EkkoSpacing.s) {
                    EkkoRadioGroup(
                        selection: $settings.insertionMethod,
                        options: InsertionMethod.allCases,
                        title: \.title,
                        detail: \.detail
                    )
                }
                EkkoCard {
                    EkkoToggleRow(
                        title: "Restore the clipboard after pasting",
                        subtitle: "Puts back whatever you had copied, a moment after Ekko pastes.",
                        isOn: $settings.restoreClipboardAfterPaste,
                        isEnabled: settings.insertionMethod == .auto || settings.insertionMethod == .paste
                    )
                }
            }
        }
    }
}

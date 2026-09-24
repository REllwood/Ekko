import SwiftUI

/// Microphone / Accessibility status with a why-line and the right call to action.
@MainActor
struct PermissionRow: View {
    let permission: Permission
    let status: PermissionStatus
    let grant: () -> Void
    let openSystemSettings: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: EkkoSpacing.m) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(EkkoColor.inkSoft)
                .frame(width: 28, height: 28)
                .background(EkkoColor.surfaceMuted, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: EkkoSpacing.s) {
                    Text(permission.title)
                        .font(EkkoType.bodySemibold)
                        .foregroundStyle(EkkoColor.ink)
                    EkkoBadge(text: statusLabel, tone: badgeTone, icon: status == .granted ? "checkmark" : nil)
                }
                Text(permission.why)
                    .font(EkkoType.caption)
                    .foregroundStyle(EkkoColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: EkkoSpacing.m)

            if status != .granted {
                Button(actionTitle, action: status == .notDetermined ? grant : openSystemSettings)
                    .buttonStyle(status == .notDetermined ? AnyButtonStyle(.ekkoPrimary(size: .small)) : AnyButtonStyle(.ekkoSecondary(size: .small)))
                    .accessibilityLabel(Text("\(actionTitle) for \(permission.title)"))
            }
        }
        .padding(.vertical, EkkoSpacing.xs)
    }

    private var symbol: String {
        switch permission {
        case .microphone: return "mic.fill"
        case .accessibility: return "accessibility"
        }
    }

    private var badgeTone: EkkoBadge.Tone {
        switch status {
        case .granted: return .success
        case .notDetermined: return .warning
        case .denied: return .danger
        }
    }

    private var statusLabel: String {
        switch status {
        case .granted: return "Granted"
        case .notDetermined: return "Not asked yet"
        case .denied: return "Not granted"
        }
    }

    private var actionTitle: String {
        status == .notDetermined ? "Grant…" : "Open Settings"
    }
}

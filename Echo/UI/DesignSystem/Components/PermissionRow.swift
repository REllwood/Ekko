import SwiftUI

/// Microphone / Accessibility status with a why-line and the right call to action.
@MainActor
struct PermissionRow: View {
    let permission: Permission
    let status: PermissionStatus
    let grant: () -> Void
    let openSystemSettings: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: EchoSpacing.m) {
            StatusDot(state: dotState, size: 9)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: EchoSpacing.s) {
                    Text(permission.title)
                        .font(EchoType.bodySemibold)
                        .foregroundStyle(EchoColor.ink)
                    EchoBadge(text: statusLabel, tone: badgeTone)
                }
                Text(permission.why)
                    .font(EchoType.caption)
                    .foregroundStyle(EchoColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: EchoSpacing.m)

            if status != .granted {
                Button(actionTitle, action: status == .notDetermined ? grant : openSystemSettings)
                    .buttonStyle(.echoSecondary())
                    .accessibilityLabel(Text("\(actionTitle) for \(permission.title)"))
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(EchoColor.success)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, EchoSpacing.xs)
    }

    private var dotState: StatusDot.State {
        switch status {
        case .granted: return .ok
        case .notDetermined: return .warning
        case .denied: return .error
        }
    }

    private var badgeTone: EchoBadge.Tone {
        switch status {
        case .granted: return .success
        case .notDetermined: return .warning
        case .denied: return .live
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
        switch permission {
        case .microphone: return status == .notDetermined ? "Grant…" : "Open System Settings"
        case .accessibility: return status == .notDetermined ? "Grant…" : "Open System Settings"
        }
    }
}

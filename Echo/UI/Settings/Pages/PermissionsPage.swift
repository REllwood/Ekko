import SwiftUI

@MainActor
struct PermissionsPage: View {
    let container: AppContainer

    var body: some View {
        VStack(alignment: .leading, spacing: EchoSpacing.l) {
            EchoCard {
                VStack(spacing: EchoSpacing.s) {
                    PermissionRow(
                        permission: .microphone,
                        status: container.permissions.microphone,
                        grant: { Task { await container.permissions.requestMicrophone() } },
                        openSystemSettings: { container.permissions.openSystemSettings(for: .microphone) }
                    )
                    EchoDivider()
                    PermissionRow(
                        permission: .accessibility,
                        status: container.permissions.accessibility,
                        grant: { container.permissions.promptAccessibility() },
                        openSystemSettings: { container.permissions.openSystemSettings(for: .accessibility) }
                    )
                }
            }

            HStack(alignment: .top, spacing: EchoSpacing.s) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 12))
                    .foregroundStyle(EchoColor.inkMuted)
                Text("Echo asks for nothing else. There is no network access, no account, and no analytics — your voice is transcribed on this Mac and then discarded.")
                    .font(EchoType.caption)
                    .foregroundStyle(EchoColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(EchoSpacing.m)
            .background(EchoColor.surfaceMuted, in: RoundedRectangle(cornerRadius: EchoRadius.control, style: .continuous))
        }
        .onAppear {
            container.permissions.refresh()
            container.permissions.startMonitoring()
        }
    }
}

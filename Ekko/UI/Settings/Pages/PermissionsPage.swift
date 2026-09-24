import SwiftUI

@MainActor
struct PermissionsPage: View {
    let container: AppContainer

    var body: some View {
        VStack(alignment: .leading, spacing: EkkoSpacing.l) {
            EkkoCard {
                VStack(spacing: EkkoSpacing.s) {
                    PermissionRow(
                        permission: .microphone,
                        status: container.permissions.microphone,
                        grant: { Task { await container.permissions.requestMicrophone() } },
                        openSystemSettings: { container.permissions.openSystemSettings(for: .microphone) }
                    )
                    EkkoDivider()
                    PermissionRow(
                        permission: .accessibility,
                        status: container.permissions.accessibility,
                        grant: { container.permissions.promptAccessibility() },
                        openSystemSettings: { container.permissions.openSystemSettings(for: .accessibility) }
                    )
                }
            }

            HStack(alignment: .top, spacing: EkkoSpacing.s) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 12))
                    .foregroundStyle(EkkoColor.inkMuted)
                Text("Ekko asks for nothing else. There is no network access, no account, and no analytics — your voice is transcribed on this Mac and then discarded.")
                    .font(EkkoType.caption)
                    .foregroundStyle(EkkoColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(EkkoSpacing.m)
            .background(EkkoColor.surfaceMuted, in: RoundedRectangle(cornerRadius: EkkoRadius.control, style: .continuous))
        }
        .onAppear {
            container.permissions.refresh()
            container.permissions.startMonitoring()
        }
    }
}

import MetlyCore
import SwiftUI

/// System permission status row: denied → "Notifications Are Off" + Open iOS Settings;
/// not asked yet → Turn On Notifications; allowed → On.
struct NotificationPermissionSection: View {
    let permission: NotificationPermission
    let requestPermission: () -> Void
    let openSettings: () -> Void

    var body: some View {
        switch permission {
        case .denied:
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label {
                        Text("Notifications Are Off")
                            .font(.headline)
                    } icon: {
                        Image(systemName: "bell.slash.fill")
                            .foregroundStyle(.red)
                    }
                    Text("Notifications are turned off for \(Brand.appName) in iOS Settings. You won’t hear about connect requests or follow-ups.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)

                Button("Open iOS Settings", action: openSettings)
            }
        case .notDetermined:
            Section {
                Button("Turn On Notifications", systemImage: "bell.badge", action: requestPermission)
            } footer: {
                Text("Get reminded to follow up on time and hear about connect requests.")
            }
        case .authorized:
            Section {
                LabeledContent {
                    Text("On")
                } label: {
                    SettingsRowLabel("Allow Notifications", systemImage: "bell.fill", color: .red)
                }
                Button("Open iOS Settings", action: openSettings)
            } footer: {
                Text("Choose sounds, banners and Lock Screen previews in iOS Settings.")
            }
        case .unknown:
            EmptyView()
        }
    }
}

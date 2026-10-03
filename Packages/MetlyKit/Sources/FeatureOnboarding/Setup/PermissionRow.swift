import MetlyDesign
import SwiftUI

/// Icon, title, subtitle and the state control (Allow / ✓ / Open Settings).
struct PermissionRow: View {
    let kind: PermissionKind
    let status: PermissionStatus
    let isRequesting: Bool
    let onAllow: () -> Void
    let onOpenSettings: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))

        layout {
            HStack(spacing: 14) {
                SettingsIcon(kind.systemImage, color: kind.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(.body)
                    Text(kind.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)

            PermissionStateControl(status: status, isRequesting: isRequesting,
                                   onAllow: onAllow, onOpenSettings: onOpenSettings)
        }
        .padding(.vertical, 4)
    }
}

private struct PermissionStateControl: View {
    let status: PermissionStatus
    let isRequesting: Bool
    let onAllow: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        Group {
            if isRequesting {
                ProgressView()
                    .frame(minWidth: 44, minHeight: 44)
            } else {
                switch status {
                case .notDetermined:
                    Button("Allow", action: onAllow)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .fontWeight(.semibold)
                case .granted:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .green)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel("Allowed")
                case .denied:
                    Button("Open Settings", action: onOpenSettings)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .accessibilityHint("Turned off. Opens iOS Settings to allow access.")
                }
            }
        }
        .transition(.opacity)
        .animation(.default, value: status)
    }
}

import SwiftUI
import UIKit

/// Rows of SETUP_PERMISSIONS. Microphone / speech, location and calendar are requested in context
/// (PLAN Q16/Q17), not here.
enum PermissionKind: String, CaseIterable, Identifiable, Hashable {
    case notifications, camera, localNetwork

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .notifications: "Notifications"
        case .camera: "Camera"
        case .localNetwork: "Nearby Devices"
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .notifications: "Know when someone wants to connect"
        case .camera: "Scan other people’s cards"
        case .localNetwork: "Connect with people around you"
        }
    }

    var systemImage: String {
        switch self {
        case .notifications: "bell.badge.fill"
        case .camera: "camera.fill"
        case .localNetwork: "antenna.radiowaves.left.and.right"
        }
    }

    /// Settings-style icon tint (matches iOS Settings conventions).
    var tint: Color {
        switch self {
        case .notifications: .red
        case .camera: .gray
        case .localNetwork: .blue
        }
    }

    /// Where "Open Settings" goes when the permission was denied.
    var settingsURL: URL? {
        switch self {
        case .notifications: URL(string: UIApplication.openNotificationSettingsURLString)
        case .camera, .localNetwork: URL(string: UIApplication.openSettingsURLString)
        }
    }
}

enum PermissionStatus: Equatable {
    case notDetermined, granted, denied

    init(_ access: LocalNetworkAccess) {
        switch access {
        case .granted: self = .granted
        case .denied: self = .denied
        case .undetermined: self = .notDetermined
        }
    }
}

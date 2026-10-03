import AVFoundation
import UserNotifications

/// Reads and requests system permissions. Swapped for a fixed stub in previews.
protocol PermissionProviding {
    func status(of kind: PermissionKind) async -> PermissionStatus
    func request(_ kind: PermissionKind) async -> PermissionStatus
}

/// Real system prompts (UNUserNotificationCenter, AVCaptureDevice, Local Network probe).
struct SystemPermissionProvider: PermissionProviding {
    var store = OnboardingStore()

    func status(of kind: PermissionKind) async -> PermissionStatus {
        switch kind {
        case .notifications:
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            return switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: .granted
            case .denied: .denied
            default: .notDetermined
            }
        case .camera:
            return switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: .granted
            case .denied, .restricted: .denied
            default: .notDetermined
            }
        case .localNetwork:
            // Probing before the first request would show the system prompt — only refresh a known answer.
            guard let known = store.localNetworkAccess, known != .undetermined else { return .notDetermined }
            let access = await LocalNetworkProbe.requestAccess(timeout: .seconds(4))
            guard access != .undetermined else { return PermissionStatus(known) }
            store.localNetworkAccess = access
            return PermissionStatus(access)
        }
    }

    func request(_ kind: PermissionKind) async -> PermissionStatus {
        switch kind {
        case .notifications:
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
            return granted ? .granted : await status(of: .notifications)
        case .camera:
            return await AVCaptureDevice.requestAccess(for: .video) ? .granted : .denied
        case .localNetwork:
            let access = await LocalNetworkProbe.requestAccess(timeout: .seconds(60))
            if access != .undetermined {
                store.localNetworkAccess = access
            }
            return PermissionStatus(access)
        }
    }
}

/// Fixed answers for previews ("mixed states").
struct PreviewPermissionProvider: PermissionProviding {
    var statuses: [PermissionKind: PermissionStatus]

    func status(of kind: PermissionKind) async -> PermissionStatus {
        statuses[kind] ?? .notDetermined
    }

    func request(_ kind: PermissionKind) async -> PermissionStatus {
        .granted
    }
}

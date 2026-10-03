@preconcurrency import AVFoundation

/// Camera availability + permission, as SCAN needs it.
enum CameraAccess: Equatable {
    /// Not asked yet — SCAN asks in context, when the tab opens.
    case undetermined
    case authorized
    /// The user said no → "Camera Access Needed" + Open Settings.
    case denied
    /// Screen Time / MDM: Settings can't fix it.
    case restricted
    /// No camera (Simulator) → unavailable state with Paste Link (+ DEBUG demo scans).
    case noCamera

    static var current: CameraAccess {
        guard AVCaptureDevice.default(for: .video) != nil else { return .noCamera }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined: return .undetermined
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .denied
        }
    }

    /// Shows the system prompt (only when undetermined) and returns the new state.
    static func request() async -> CameraAccess {
        guard current == .undetermined else { return current }
        return await AVCaptureDevice.requestAccess(for: .video) ? .authorized : .denied
    }
}

@preconcurrency import AVFoundation

/// Owns the fallback `AVCaptureSession` and starts / stops it off the main actor
/// (`startRunning()` blocks). Calls are serialised by the actor.
actor CaptureSessionRunner {
    /// Read on the main actor only to configure it and attach the preview layer before it runs.
    nonisolated(unsafe) let session = AVCaptureSession()

    func start() {
        if !session.isRunning { session.startRunning() }
    }

    func stop() {
        if session.isRunning { session.stopRunning() }
    }
}

@preconcurrency import AVFoundation

/// Bridges one `AVCapturePhotoOutput` capture to async/await.
nonisolated final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    enum CaptureError: Error { case noImage }

    /// Set before the capture starts, resumed once by the photo output's callback.
    private var continuation: CheckedContinuation<Data, any Error>?

    @MainActor
    func capture(from output: AVCapturePhotoOutput) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {
        if let error {
            continuation?.resume(throwing: error)
        } else if let data = photo.fileDataRepresentation() {
            continuation?.resume(returning: data)
        } else {
            continuation?.resume(throwing: CaptureError.noImage)
        }
        continuation = nil
    }
}

@preconcurrency import AVFoundation
import UIKit

/// A view whose layer is the camera preview.
final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        // Guaranteed by `layerClass`.
        layer as! AVCaptureVideoPreviewLayer
    }
}

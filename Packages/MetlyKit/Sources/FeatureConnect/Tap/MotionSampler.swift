import CoreMotion
import Foundation

/// Streams user-acceleration magnitudes (g, gravity removed) for bump detection.
/// No permission is needed for device motion.
nonisolated enum MotionSampler {
    static let interval: TimeInterval = 1.0 / 60.0

    /// Starts device-motion updates on a private queue. Stop with `manager.stopDeviceMotionUpdates()`.
    static func userAccelerationMagnitudes(from manager: CMMotionManager) -> AsyncStream<Double> {
        let (stream, continuation) = AsyncStream.makeStream(of: Double.self, bufferingPolicy: .bufferingNewest(8))
        let queue = OperationQueue()
        queue.name = "app.nameshake.ios.connect.motion"
        queue.maxConcurrentOperationCount = 1
        manager.deviceMotionUpdateInterval = interval
        manager.startDeviceMotionUpdates(to: queue) { @Sendable motion, _ in
            guard let acceleration = motion?.userAcceleration else { return }
            continuation.yield(BumpDetector.magnitude(x: acceleration.x, y: acceleration.y, z: acceleration.z))
        }
        return stream
    }
}

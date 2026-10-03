import Foundation
import Photos

/// Saves exported images with **add-only** Photos access (`NSPhotoLibraryAddUsageDescription`),
/// requested in context the first time the user taps Save.
nonisolated enum PhotoLibrarySaver {
    enum Failure: Error, Equatable {
        /// The user denied (or a profile restricts) adding to Photos — offer Settings.
        case accessDenied
        case saveFailed
    }

    static func save(imageData: Data) async throws {
        let status = await authorizationStatus()
        guard status == .authorized || status == .limited else { throw Failure.accessDenied }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: imageData, options: nil)
            }
        } catch {
            throw Failure.saveFailed
        }
    }

    private static func authorizationStatus() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard current == .notDetermined else { return current }
        return await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    }
}

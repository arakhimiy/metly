// SyncEngine — images, after the records: profile photo/logo uploads and downloads, peers' avatar
// downloads, and the hashing / content-type helpers they use.
import CryptoKit
import Foundation
import MetlyCore
import MetlyNetworking
import SwiftData

extension SyncEngine {
    /// Avatars are fetched this many at a time; bigger files are ignored.
    private static let avatarDownloadWidth = 4
    private static let maxAvatarBytes = 5_000_000

    /// Images go after the records and never fail the pass: an upload the server can't take (no
    /// object storage, `503`) must not hold back people and cards. They're tried again next pass.
    func syncImages() async throws {
        do {
            try await pushProfileImages()
            try await pullProfileImages()
            try await pullConnectionAvatars()
        } catch {
            let apiError = APIError(error)
            switch apiError {
            case .cancelled, .unauthorized: throw apiError
            default: break
            }
        }
    }

    private func pushProfileImages() async throws {
        let context = container.mainContext
        // The server needs the profile record before an image can be attached to it.
        guard let profile = context.currentProfile(), profile.syncState == .synced else { return }
        for kind in ProfileImageKind.allCases {
            let data = kind == .photo ? profile.photoData : profile.logoData
            let localHash = data.map(Self.sha256)
            guard localHash != state.imageState(kind).syncedHash else { continue }
            let serverProfile: ProfileDTO
            if let data {
                let ticket = try await api.profile.requestImageUpload(kind, UploadTicketRequest(contentType: Self.contentType(of: data),
                                                                                                byteSize: data.count))
                try await api.profile.upload(data, using: ticket)
                serverProfile = try await api.profile.commitImageUpload(kind, uploadID: ticket.uploadID)
            } else {
                serverProfile = try await api.profile.deleteImage(kind)
            }
            try checkpoint()
            let url = kind == .photo ? serverProfile.photoURL : serverProfile.logoURL
            state.setImageState(SyncStateStore.ImageState(syncedHash: localHash, syncedURL: url, remoteURL: url), for: kind)
        }
    }

    private func pullProfileImages() async throws {
        let context = container.mainContext
        guard let profile = context.currentProfile() else { return }
        var changed = false
        for kind in ProfileImageKind.allCases {
            var image = state.imageState(kind)
            let data = kind == .photo ? profile.photoData : profile.logoData
            // Only when there's no unsynced local change and the server has something new.
            guard data.map(Self.sha256) == image.syncedHash, image.remoteURL != image.syncedURL else { continue }
            var downloaded: Data?
            if let url = image.remoteURL {
                do {
                    downloaded = try await api.profile.downloadAsset(url)
                    try checkpoint()
                } catch let error as APIError where error.statusCode == 404 {
                    try checkpoint()
                    image.syncedURL = url   // gone — don't retry forever
                    state.setImageState(image, for: kind)
                    continue
                }
            }
            switch kind {
            case .photo: profile.photoData = downloaded
            case .logo: profile.logoData = downloaded
            }
            image.syncedHash = downloaded.map(Self.sha256)
            image.syncedURL = image.remoteURL
            state.setImageState(image, for: kind)
            changed = true
        }
        if changed { try context.save() }
    }

    /// Peers' profile photos (server-owned `avatarUrl`) → `Connection.avatarData`. Each URL is
    /// fetched once, a few at a time off the main actor; failures are retried on the next pass and
    /// never fail the sync. Only bytes put there by this method are ever cleared.
    private func pullConnectionAvatars() async throws {
        let context = container.mainContext
        var avatars = state.avatars
        var downloads: [(id: UUID, url: URL)] = []
        var changed = false
        for (id, avatar) in avatars where avatar.needsDownload {
            guard let connection = context.record(Connection.self, id: id), connection.deletedAt == nil else {
                avatars[id] = nil
                continue
            }
            if let url = avatar.remoteURL {
                downloads.append((id, url))
            } else {
                if avatar.syncedURL != nil, connection.avatarData != nil {
                    connection.avatarData = nil
                    changed = true
                }
                avatars[id] = nil
            }
        }

        if !downloads.isEmpty {
            let api = api
            let fetch: @Sendable (UUID, URL) async -> (UUID, URL, Result<Data, APIError>) = { id, url in
                do {
                    return (id, url, .success(try await api.profile.downloadAsset(url)))
                } catch {
                    return (id, url, .failure(APIError(error)))
                }
            }
            let results = await withTaskGroup(of: (UUID, URL, Result<Data, APIError>).self) { group in
                var queue = downloads[...]
                for _ in 0..<min(Self.avatarDownloadWidth, queue.count) {
                    let next = queue.removeFirst()
                    group.addTask { await fetch(next.id, next.url) }
                }
                var results: [(UUID, URL, Result<Data, APIError>)] = []
                for await result in group {
                    results.append(result)
                    if let next = queue.popFirst() {
                        group.addTask { await fetch(next.id, next.url) }
                    }
                }
                return results
            }
            try checkpoint()
            for (id, url, result) in results {
                switch result {
                case .success(let data):
                    guard let connection = context.record(Connection.self, id: id), connection.deletedAt == nil else {
                        avatars[id] = nil
                        continue
                    }
                    if data.count <= Self.maxAvatarBytes {
                        connection.avatarData = data
                        changed = true
                    }
                    avatars[id]?.syncedURL = url
                case .failure(let error) where error.statusCode == 404 || error.statusCode == 410:
                    avatars[id]?.syncedURL = url   // gone — don't retry forever
                case .failure:
                    break   // offline / server trouble: next pass
                }
            }
        }
        state.avatars = avatars
        if changed { try context.save() }
    }

    // MARK: Helpers

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func contentType(of data: Data) -> String {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if bytes.count >= 12, String(decoding: bytes[4..<12], as: UTF8.self).hasPrefix("ftypheic") { return "image/heic" }
        return "application/octet-stream"
    }
}

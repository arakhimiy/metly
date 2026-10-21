import Foundation
import MetlyNetworking

/// Device-local sync bookkeeping (UserDefaults — the SwiftData schema is frozen and none of this
/// is secret). Cleared on sign-out together with the store.
@MainActor
public final class SyncStateStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Opaque `/v1/sync` cursor; nil → next pull is a full snapshot.
    public var cursor: String? {
        get { defaults.string(forKey: Keys.cursor) }
        set { defaults.set(newValue, forKey: Keys.cursor) }
    }

    public var lastSyncedAt: Date? {
        get { defaults.object(forKey: Keys.lastSyncedAt) as? Date }
        set { defaults.set(newValue, forKey: Keys.lastSyncedAt) }
    }

    /// Stable per-install id (device registration, deferred-link claim, push `deviceId`).
    public var installID: String {
        if let id = defaults.string(forKey: Keys.installID) { return id }
        let id = UUID().uuidString.lowercased()
        defaults.set(id, forKey: Keys.installID)
        return id
    }

    /// The account the local store belongs to (wipe before signing in as someone else).
    public var lastUserID: UUID? {
        get { defaults.string(forKey: Keys.lastUserID).flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: Keys.lastUserID) }
    }

    // MARK: Rejected pushes

    /// Records the server rejected (plan limit / validation) at a given `updatedAt`. They are not
    /// pushed again until edited (their `updatedAt` changes), so a rejection never loops.
    public func isRejected(_ id: UUID, updatedAt: Date) -> Bool {
        guard let stamp = rejected[id.uuidString] else { return false }
        return abs(stamp - updatedAt.timeIntervalSinceReferenceDate) < 0.000_5
    }

    public func markRejected(_ id: UUID, updatedAt: Date) {
        var map = rejected
        map[id.uuidString] = updatedAt.timeIntervalSinceReferenceDate
        rejected = map
    }

    public func clearRejected(_ id: UUID) {
        var map = rejected
        if map.removeValue(forKey: id.uuidString) != nil { rejected = map }
    }

    public var rejectedIDs: Set<UUID> { Set(rejected.keys.compactMap(UUID.init(uuidString:))) }

    private var rejected: [String: Double] {
        get { defaults.dictionary(forKey: Keys.rejected) as? [String: Double] ?? [:] }
        set { defaults.set(newValue, forKey: Keys.rejected) }
    }

    // MARK: Profile images

    public struct ImageState: Codable, Equatable, Sendable {
        /// SHA-256 of the local bytes at the last upload/download.
        public var syncedHash: String?
        /// Server URL matching those bytes.
        public var syncedURL: URL?
        /// Latest URL the server reported.
        public var remoteURL: URL?
    }

    public func imageState(_ kind: ProfileImageKind) -> ImageState {
        guard let data = defaults.data(forKey: Keys.image(kind)),
              let state = try? JSONDecoder().decode(ImageState.self, from: data) else { return ImageState() }
        return state
    }

    public func setImageState(_ state: ImageState, for kind: ProfileImageKind) {
        defaults.set(try? JSONEncoder().encode(state), forKey: Keys.image(kind))
    }

    /// Records the photo/logo URLs from any server profile we saw.
    public func noteRemoteImages(of profile: ProfileDTO) {
        for (kind, url) in [(ProfileImageKind.photo, profile.photoURL), (.logo, profile.logoURL)] {
            var state = imageState(kind)
            if state.remoteURL != url {
                state.remoteURL = url
                setImageState(state, for: kind)
            }
        }
    }

    // MARK: Connection avatars

    /// A peer's photo: the server-owned `avatarUrl` vs. the URL whose bytes are in `Connection.avatarData`.
    public struct AvatarState: Codable, Equatable, Sendable {
        /// Latest URL the server reported (nil = no photo).
        public var remoteURL: URL?
        /// URL of the bytes we stored (nil = we stored nothing).
        public var syncedURL: URL?

        public var needsDownload: Bool { remoteURL != syncedURL }
    }

    /// Keyed by connection id.
    public var avatars: [UUID: AvatarState] {
        get {
            guard let data = defaults.data(forKey: Keys.avatars),
                  let map = try? JSONDecoder().decode([String: AvatarState].self, from: data) else { return [:] }
            return Dictionary(uniqueKeysWithValues: map.compactMap { key, value in UUID(uuidString: key).map { ($0, value) } })
        }
        set {
            let map = Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.uuidString, $0.value) })
            defaults.set(try? JSONEncoder().encode(map), forKey: Keys.avatars)
        }
    }

    /// Records the avatar URLs of server connections we applied (`nil` = the server has none).
    public func noteRemoteAvatars(_ urls: [UUID: URL?]) {
        guard !urls.isEmpty else { return }
        var map = avatars
        var changed = false
        for (id, url) in urls {
            if let known = map[id] {
                guard known.remoteURL != url else { continue }
                map[id]?.remoteURL = url
            } else {
                guard let url else { continue }   // never had a photo, still none
                map[id] = AvatarState(remoteURL: url, syncedURL: nil)
            }
            changed = true
        }
        if changed { avatars = map }
    }

    public func forgetAvatars(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        var map = avatars
        let before = map.count
        for id in ids { map[id] = nil }
        if map.count != before { avatars = map }
    }

    /// Forget everything about the signed-out account (keeps `installID`).
    public func reset() {
        for key in [Keys.cursor, Keys.lastSyncedAt, Keys.rejected, Keys.lastUserID, Keys.avatars]
            + ProfileImageKind.allCases.map(Keys.image) {
            defaults.removeObject(forKey: key)
        }
    }

    private enum Keys {
        static let cursor = "sync.cursor"
        static let lastSyncedAt = "sync.lastSyncedAt"
        static let rejected = "sync.rejected"
        static let installID = "sync.installID"
        static let lastUserID = "sync.lastUserID"
        static let avatars = "sync.avatars"
        static func image(_ kind: ProfileImageKind) -> String { "sync.image.\(kind.rawValue)" }
    }
}

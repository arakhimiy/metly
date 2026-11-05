import Foundation

/// The last known plan, kept on the device so Pro holds from the first frame after launch and
/// while offline, until StoreKit's `currentEntitlements` has been re-read.
nonisolated struct EntitlementCache {
    private let store: UserDefaults
    private static let key = "metly.entitlements.lastKnown"

    init(store: UserDefaults = .standard) {
        self.store = store
    }

    /// The cached Pro snapshot while its period hasn't ended; nil for Free or once it has.
    func load(now: Date) -> EntitlementSnapshot? {
        guard let data = store.data(forKey: Self.key),
              let snapshot = try? JSONDecoder().decode(EntitlementSnapshot.self, from: data),
              snapshot.isPro,
              (snapshot.renewsAt ?? .distantFuture) > now else { return nil }
        return snapshot
    }

    func save(_ snapshot: EntitlementSnapshot) {
        if snapshot.isPro, let data = try? JSONEncoder().encode(snapshot) {
            store.set(data, forKey: Self.key)
        } else {
            store.removeObject(forKey: Self.key)
        }
    }
}

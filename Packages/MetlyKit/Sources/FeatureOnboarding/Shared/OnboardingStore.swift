import Foundation

/// Identity provider an account was created with (drives the "From your Apple ID" footer).
nonisolated enum AuthProvider: String, Codable, Sendable {
    case apple, google
}

/// Name and email suggested by the identity provider. Kept until SETUP_PROFILE is completed,
/// because Apple only sends the name on the very first authorization.
nonisolated struct SetupPrefill: Codable, Equatable, Sendable {
    var fullName: String?
    var email: String?
    var provider: AuthProvider

    var hasValues: Bool {
        !(fullName ?? "").isEmpty || !(email ?? "").isEmpty
    }
}

/// Last known Local Network result. iOS has no API that reads it without prompting.
nonisolated enum LocalNetworkAccess: String, Codable, Sendable {
    case granted, denied, undetermined
}

/// Module-internal, device-local persistence for the onboarding flow (never synced).
///
/// - `setupPrefill` — written after sign-in when the account needs setup, read by SETUP_PROFILE,
///   cleared when setup finishes.
/// - `pendingInviteSlug` — written when the user taps "Connect with {first}" on DEFERRED_WELCOME.
///   When onboarding ends (end of SETUP_PERMISSIONS, or straight after sign-in for an existing account)
///   `OnboardingCoordinator` opens that person's card (`.scannedCard` in the Scan tab) instead of
///   CARD_CREATE and clears the slug.
/// - `localNetworkAccess` — remembered result of the Local Network probe.
nonisolated struct OnboardingStore {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var setupPrefill: SetupPrefill? {
        get {
            guard let data = defaults.data(forKey: Keys.setupPrefill) else { return nil }
            return try? JSONDecoder().decode(SetupPrefill.self, from: data)
        }
        nonmutating set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.setupPrefill)
            } else {
                defaults.removeObject(forKey: Keys.setupPrefill)
            }
        }
    }

    var pendingInviteSlug: String? {
        get { defaults.string(forKey: Keys.pendingInviteSlug).flatMap { $0.isEmpty ? nil : $0 } }
        nonmutating set { defaults.set(newValue, forKey: Keys.pendingInviteSlug) }
    }

    var localNetworkAccess: LocalNetworkAccess? {
        get { defaults.string(forKey: Keys.localNetworkAccess).flatMap(LocalNetworkAccess.init(rawValue:)) }
        nonmutating set { defaults.set(newValue?.rawValue, forKey: Keys.localNetworkAccess) }
    }

    enum Keys {
        static let setupPrefill = "onboarding.setupPrefill"
        static let pendingInviteSlug = "onboarding.pendingInviteSlug"
        static let localNetworkAccess = "onboarding.localNetworkAccess"
    }
}

extension OnboardingStore {
    /// Throwaway store for previews (separate suite so it never touches real data).
    static func preview(prefill: SetupPrefill? = nil, pendingInviteSlug: String? = nil) -> OnboardingStore {
        let suite = "preview.onboarding.\(UUID().uuidString)"
        let store = OnboardingStore(defaults: UserDefaults(suiteName: suite) ?? .standard)
        store.setupPrefill = prefill
        store.pendingInviteSlug = pendingInviteSlug
        return store
    }
}

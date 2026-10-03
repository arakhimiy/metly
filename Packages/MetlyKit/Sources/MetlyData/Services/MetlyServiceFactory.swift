import Foundation
import MetlyCore
import SwiftData

/// Builds the live service graph for the app target. The Data & Sync agent replaces the
/// local stand-ins below with the real API-backed implementations (keep this signature).
public enum MetlyServiceFactory {
    @MainActor public static func makeServices(container: ModelContainer) -> AppServices {
        let local = LocalOnlyServices(container: container)
        return AppServices(auth: local, sync: local, deferredLinks: local, subscriptions: local, push: local)
    }
}

/// Temporary offline-only implementation so the app runs before the backend layer exists.
@MainActor
final class LocalOnlyServices: AuthServicing, SyncServicing, DeferredLinkServicing, SubscriptionVerifying, PushRegistering {
    private let container: ModelContainer
    var isSignedIn: Bool
    var accountEmail: String?
    var status: SyncStatus = .idle
    var lastSyncedAt: Date?

    init(container: ModelContainer) {
        self.container = container
        isSignedIn = container.mainContext.currentProfile() != nil
    }

    func signIn(apple: AppleSignInCredential) async throws -> AuthResult {
        isSignedIn = true
        accountEmail = apple.email
        let name = apple.fullName.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default) }
        return AuthResult(needsSetup: container.mainContext.currentProfile()?.isSetupComplete != true, suggestedName: name, email: apple.email)
    }

    func signIn(google: GoogleSignInCredential) async throws -> AuthResult {
        isSignedIn = true
        accountEmail = google.email
        return AuthResult(needsSetup: container.mainContext.currentProfile()?.isSetupComplete != true, suggestedName: google.fullName, email: google.email)
    }

    func signOut() async {
        try? MetlyModelContainer.wipe(container.mainContext)
        isSignedIn = false
    }

    func deleteAccount() async throws { await signOut() }
    func requestDataExport() async throws {}
    func requestSync() {}
    func syncNow() async {}
    func claimPendingInvite() async -> DeferredInvite? { nil }
    func verify(signedTransaction jws: String) async throws -> Plan { .pro }
    func register(deviceToken: Data) async {}
}

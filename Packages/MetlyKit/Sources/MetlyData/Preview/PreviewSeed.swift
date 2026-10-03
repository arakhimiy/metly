import Foundation
import MetlyCore
import MetlyNetworking
import SwiftData
import SwiftUI

/// Demo data mirroring the prototype (SPEC Appendix A). Used by previews, UI tests and the mock server.
///
/// Built from `MockSeed` (MetlyNetworking), so every record id matches what `MockMetlyServer`
/// serves — a device seeded with demo data syncs against the mock without duplicates.
public enum PreviewSeed {
    public enum Variant: Sendable {
        /// Profile + 2 cards + people, follow-ups, an active event, requests.
        case full
        /// Profile + 1 card, nothing else (empty states).
        case empty
        /// Nothing (onboarding / setup).
        case signedOut
    }

    public static let profileID = MockSeed.profileID
    public static let workCardID = MockSeed.workCardID
    public static let personalCardID = MockSeed.personalCardID
    public static let eventID = MockSeed.eventID
    public static let firstConnectionID = MockSeed.connectionIDs[0]

    public static func insert(_ variant: Variant, into context: ModelContext) {
        guard variant != .signedOut else { return }
        let demo = MockSeed.demoAccount(now: .now)
        let account = variant == .full ? demo : demo.minimal

        if let dto = account.profile {
            let profile = Profile(id: dto.id)
            context.insert(profile)
            profile.apply(dto)
            profile.syncState = .synced
        }
        for dto in account.cards {
            let card = Card(dto: dto)
            context.insert(card)
            card.syncState = .synced
        }
        for dto in account.events {
            let event = Event(dto: dto)
            context.insert(event)
            event.syncState = .synced
        }
        // Inserted after events/connections so relationships resolve (fetches see pending inserts).
        for dto in account.connections {
            Connection(dto: dto, in: context).syncState = .synced
        }
        for dto in account.followUps {
            FollowUp(dto: dto, in: context).syncState = .synced
        }
        for dto in account.connectRequests {
            let request = ConnectRequest(dto: dto)
            context.insert(request)
            request.syncState = .synced
        }
        try? context.save()
    }
}

@MainActor
public extension View {
    /// Injects router, services, a mock-backed `MetlyClient` and an in-memory seeded store.
    /// Use in every `#Preview`.
    func metlyPreview(_ seed: PreviewSeed.Variant = .full, plan: Plan = .free, online: Bool = true) -> some View {
        let container = MetlyModelContainer.preview(seed)
        return self
            .modelContainer(container)
            .environment(AppRouter(phase: .main))
            .environment(AppServices.preview(plan: plan, online: online))
            .environment(MetlyClient.preview(container: container, online: online))
    }
}

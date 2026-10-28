import FeatureHome
import Foundation
import MetlyCore
import MetlyData
import MetlyWidgetKit
import SwiftData

/// Starts widget publishing. The app calls this once in `MetlyApp.init`, after the store is created:
///
///     WidgetSync.start(container: container)
enum WidgetSync {
    @MainActor
    static func start(container: ModelContainer) {
        // Widget "Done" taps withdraw the reminder's notification and wait in the App Group queue until the
        // publisher applies them (on activation, after a debounce). Until then the store still has the
        // reminder open, so the notification scheduler must not re-add it — e.g. its first pass at launch,
        // a "Snooze 1 Day" action or a background sync save, all of which can run before the queue is applied.
        FollowUpNotificationScheduler.pendingCompletionIDs = {
            WidgetSnapshotStore.appGroup.pendingFollowUpCompletionIDs()
        }
        WidgetSnapshotPublisher.start(source: AppWidgetSnapshotSource(container: container))
    }
}

/// Bridges SwiftData to `WidgetSnapshotPublisher` (MetlyWidgetKit can't import MetlyData — the widget
/// extension links it and must stay free of the store). Plain mapping only; the rules (public fields,
/// QR payloads, ordering, counts) live in `WidgetSnapshotBuilder` and are unit-tested there.
@MainActor
final class AppWidgetSnapshotSource: WidgetSnapshotSource {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func snapshotInput(now: Date) -> WidgetSnapshotInput? {
        let context = container.mainContext
        guard let profile = context.currentProfile(), profile.isSetupComplete else { return nil }

        let cards = (try? context.fetch(Card.live)) ?? []
        let followUps = ((try? context.fetch(FollowUp.open)) ?? []).filter { $0.connection?.isDeleted != true }

        let cutoff = now.addingTimeInterval(-WidgetSnapshot.recentConnectionWindow)
        let recent = FetchDescriptor<Connection>(predicate: #Predicate {
            $0.deletedAt == nil && !$0.isBlocked && $0.createdAt >= cutoff
        })
        let connectionDates = ((try? context.fetch(recent)) ?? []).map(\.createdAt)

        return WidgetSnapshotInput(
            owner: WidgetSnapshotInput.Owner(
                fullName: profile.fullName,
                jobTitle: profile.jobTitle,
                company: profile.company,
                photoData: profile.photoData,
                logoData: profile.logoData,
                contactFields: profile.contactFields,
                phoneLabel: profile.phoneLabel,
                additionalPhones: profile.additionalPhones,
                contacts: profile.contacts,
                linksPaused: profile.linksPaused
            ),
            cards: cards.map {
                WidgetSnapshotInput.Card(id: $0.id, name: $0.name, slug: $0.slug, sortOrder: $0.sortOrder, design: $0.design,
                                         visibleContactIDs: $0.visibleContactIDs)
            },
            defaultCardID: context.defaultCard()?.id,
            shareCardID: context.cardToShare()?.id,
            openFollowUps: followUps.map { followUp in
                WidgetSnapshotInput.FollowUp(
                    id: followUp.id,
                    title: followUp.title,
                    dueAt: followUp.dueAt,
                    channel: followUp.channel,
                    personName: followUp.connection?.fullName,
                    connectionID: followUp.connection?.id,
                    personContext: followUp.connection.flatMap(Self.context(of:))
                )
            },
            connectionDates: connectionDates,
            activeEventName: context.activeEvent()?.name
        )
    }

    func completeFollowUps(_ completions: [WidgetFollowUpCompletion]) -> Set<UUID> {
        let context = container.mainContext
        var changed = false
        for completion in completions {
            guard let followUp = context.record(FollowUp.self, id: completion.followUpID),
                  !followUp.isDone, !followUp.isDeleted
            else { continue }   // already done, deleted or unknown → settled, nothing to apply
            followUp.isDone = true
            followUp.completedAt = completion.completedAt
            followUp.markChanged()
            changed = true
        }
        if changed {
            do {
                try context.save()
            } catch {
                return []   // keep the queue; retried on the next activation
            }
        }
        return Set(completions.map(\.followUpID))
    }

    /// "{event or company}" — the second part of "{name} · {event or company}" (as in FOLLOWUPS).
    private static func context(of person: Connection) -> String? {
        [person.context.eventName, person.company, person.context.place]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }
}

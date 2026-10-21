import Foundation
import MetlyCapture
import MetlyCore
import MetlyData
import SwiftData

/// Mutations behind People's buttons. Everything is a soft change (`markChanged` / `markDeleted`)
/// so the sync engine picks it up; each returns what the UI needs for its toast / Undo.
enum PeopleActions {

    // MARK: Remove / block

    /// Removes the person (one-sided) and their open reminders. Returns the Undo action.
    ///
    /// Undo works from a snapshot, not the model objects: the sync engine pushes the tombstone ~1.5 s later
    /// and hard-deletes the local records once the server confirms (the follow-ups cascade with them) —
    /// well inside the 4 s Undo window. Restoring then re-creates the records with the same ids.
    @discardableResult
    static func remove(_ person: Connection, in context: ModelContext) -> @MainActor () -> Void {
        let snapshot = RemovedPerson(person)
        let reminders = person.followUps.filter { !$0.isDone && !$0.isDeleted }
        reminders.forEach { $0.markDeleted() }
        person.markDeleted()
        try? context.save()
        return {
            snapshot.restore(in: context)
            try? context.save()
        }
    }

    static func block(_ person: Connection, in context: ModelContext) {
        person.isBlocked = true
        person.markChanged()
        try? context.save()
    }

    static func unblock(_ person: Connection, in context: ModelContext) {
        person.isBlocked = false
        person.markChanged()
        try? context.save()
    }

    // MARK: Follow-ups

    /// Marks a reminder done. Returns the Undo action.
    @discardableResult
    static func markDone(_ followUp: FollowUp, in context: ModelContext) -> @MainActor () -> Void {
        followUp.isDone = true
        followUp.completedAt = .now
        followUp.markChanged()
        try? context.save()
        return {
            followUp.isDone = false
            followUp.completedAt = nil
            followUp.markChanged()
            try? context.save()
        }
    }

    // MARK: Connect requests

    /// Accepts an incoming request locally: creates (or refreshes) the connection with their card,
    /// tags it with the active event and marks the request accepted (synced to the server).
    @discardableResult
    static func accept(_ request: ConnectRequest, in context: ModelContext, now: Date = .now) -> Connection {
        let activeEvent = context.activeEvent()
        let meeting = PlaceText.normalized(MeetingContext(eventID: activeEvent?.id,
                                                          eventName: activeEvent?.name ?? request.eventName,
                                                          place: nonEmpty(activeEvent?.place),
                                                          city: nonEmpty(activeEvent?.city),
                                                          metAt: now))

        let peerID = request.peerUserID
        var existing = FetchDescriptor<Connection>(predicate: #Predicate { $0.remoteUserID == peerID && $0.deletedAt == nil })
        existing.fetchLimit = 1

        let person: Connection
        if let known = try? context.fetch(existing).first {
            person = known
            if CaptureDraft.isDifferentMeeting(known.context, meeting) {
                known.previousMeetings.insert(known.context, at: 0)
            }
            known.context = meeting
            known.isBlocked = false
        } else {
            person = Connection(fullName: request.peerName, jobTitle: request.peerTitle,
                                company: request.peerCompany, source: .connectRequest, context: meeting)
            person.remoteUserID = request.peerUserID
            context.insert(person)
        }

        if let card = request.peerCard {
            person.theirCard = card
            for field in card.fields where !field.isEmpty && person.value(for: field.kind).isEmpty {
                person.setValue(field.value, for: field.kind)
            }
        }
        person.mySharedCardID = request.myCardID ?? context.cardToShare()?.id
        person.event = activeEvent
        person.markChanged()

        request.status = .accepted
        request.respondedAt = now
        request.markChanged()
        settleOtherRequests(from: peerID, except: request.id, in: context, now: now)
        try? context.save()
        return person
    }

    /// Connecting settles every other pending request between the two people on the server
    /// (docs/api/README.md); mirror that locally so People › Requests doesn't ask again. Not marked
    /// changed: the server already does it and the next pull confirms.
    private static func settleOtherRequests(from peerID: UUID, except requestID: UUID, in context: ModelContext, now: Date) {
        let incoming = ConnectRequestDirection.incoming.rawValue
        let pending = ConnectRequestStatus.pending.rawValue
        let descriptor = FetchDescriptor<ConnectRequest>(predicate: #Predicate {
            $0.peerUserID == peerID && $0.id != requestID && $0.directionRaw == incoming && $0.statusRaw == pending
        })
        for other in (try? context.fetch(descriptor)) ?? [] {
            other.status = .accepted
            other.respondedAt = now
        }
    }

    /// Declines without notifying the requester (PLAN Q9).
    static func decline(_ request: ConnectRequest, in context: ModelContext, now: Date = .now) {
        request.status = .declined
        request.respondedAt = now
        request.markChanged()
        try? context.save()
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return value
    }
}

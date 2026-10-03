import Foundation
import MetlyCapture
import MetlyCore
import MetlyData
import SwiftData

/// Accepting while offline: `MetlyClient.accept` queues the accept and returns nil. Accepting must
/// still land on CONNECTED (PLAN Q11), so the connection is created locally from the request; the
/// server's copy merges into it by `remoteUserID` on the next sync.
enum OfflineAccept {
    @discardableResult
    static func connection(for request: ConnectRequest, sharing cardID: UUID, in context: ModelContext,
                           now: Date = .now) -> Connection {
        let event = context.activeEvent()
        let meeting = MeetingContext(eventID: event?.id,
                                     eventName: event?.name ?? request.eventName,
                                     place: nonEmpty(event?.place),
                                     city: nonEmpty(event?.city),
                                     metAt: now)

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
            person = Connection(fullName: request.peerName, jobTitle: request.peerTitle, company: request.peerCompany,
                                source: request.method == .tapPhones ? .tapPhones : .nearby, context: meeting)
            person.remoteUserID = peerID
            context.insert(person)
        }

        if let card = request.peerCard {
            person.theirCard = card
            for field in card.fields where !field.isEmpty && person.value(for: field.kind).isEmpty {
                person.setValue(field.value, for: field.kind)
            }
        }
        person.mySharedCardID = cardID
        person.event = event
        person.markChanged()
        try? context.save()
        return person
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return value
    }
}

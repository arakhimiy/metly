import Foundation
import MetlyCapture
import MetlyCore
import MetlyData
import SwiftData

/// Creates and finds the `Connection` records behind Scan's "Add to People", offline Connect,
/// vCard Save and paper Save. New records are stamped with the active event (SPEC §3.17).
enum ScanConnectionFactory {
    /// Someone's Tanishly card → a connection carrying their card snapshot and visible fields.
    @discardableResult
    static func insertConnection(from snapshot: CardSnapshot, remoteUserID: UUID?, sharedCardID: UUID? = nil,
                                 source: ConnectionSource = .scanQR, in context: ModelContext,
                                 now: Date = .now) -> Connection {
        let connection = makeConnection(fullName: snapshot.fullName, jobTitle: snapshot.jobTitle,
                                        company: snapshot.company, fields: snapshot.fields,
                                        source: source, in: context, now: now)
        connection.remoteUserID = remoteUserID
        connection.theirCard = snapshot
        connection.mySharedCardID = sharedCardID
        try? context.save()
        return connection
    }

    /// A foreign vCard or a paper card → a plain connection (no card snapshot).
    @discardableResult
    static func insertConnection(from draft: PaperCardDraft, source: ConnectionSource, in context: ModelContext,
                                 now: Date = .now) -> Connection {
        let connection = makeConnection(fullName: displayName(for: draft), jobTitle: draft.jobTitle,
                                        company: draft.company, fields: draft.fields,
                                        source: source, in: context, now: now)
        try? context.save()
        return connection
    }

    /// "Where you met" right now: the active event and its place, else just the time.
    static func currentMeeting(in context: ModelContext, now: Date = .now) -> (context: MeetingContext, event: Event?) {
        guard let event = context.activeEvent() else { return (MeetingContext(metAt: now), nil) }
        let meeting = MeetingContext(eventID: event.id, eventName: event.name,
                                     place: PlaceText.normalizedPlace(event.place, city: event.city),
                                     city: event.city.isEmpty ? nil : event.city, metAt: now)
        return (meeting, event)
    }

    /// Name to save: the person's name, else the company (a card can be a company card).
    static func displayName(for draft: PaperCardDraft) -> String {
        let name = draft.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? draft.company.trimmingCharacters(in: .whitespacesAndNewlines) : name
    }

    // MARK: Matching

    /// The live connection to a Tanishly user, if the owner already has them in People.
    static func existing(remoteUserID: UUID?, among people: [Connection]) -> Connection? {
        guard let remoteUserID else { return nil }
        return people.first { $0.remoteUserID == remoteUserID && !$0.isDeleted }
    }

    /// Same as above, fetched from the store (blocked people included, so they aren't duplicated).
    static func existing(remoteUserID: UUID?, in context: ModelContext) -> Connection? {
        guard let remoteUserID else { return nil }
        var descriptor = FetchDescriptor<Connection>(predicate: #Predicate { $0.remoteUserID == remoteUserID && $0.deletedAt == nil })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// A live connection sharing a phone number (last 9 digits), email or Telegram handle.
    static func existing(matching fields: [ContactField], among people: [Connection]) -> Connection? {
        let phone = fields.first { $0.kind == .phone }.map { phoneKey($0.value) } ?? ""
        let email = fields.first { $0.kind == .email }?.value.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        let telegram = fields.first { $0.kind == .telegram }.flatMap { ContactLinks.telegramHandle($0.value)?.lowercased() } ?? ""
        guard !(phone.isEmpty && email.isEmpty && telegram.isEmpty) else { return nil }
        return people.first { person in
            guard !person.isDeleted else { return false }
            if phone.count >= 7, phoneKey(person.phone) == phone { return true }
            if !email.isEmpty, person.email.trimmingCharacters(in: .whitespaces).lowercased() == email { return true }
            if !telegram.isEmpty, ContactLinks.telegramHandle(person.telegram)?.lowercased() == telegram { return true }
            return false
        }
    }

    // MARK: Private

    private static func makeConnection(fullName: String, jobTitle: String, company: String, fields: [ContactField],
                                       source: ConnectionSource, in context: ModelContext, now: Date) -> Connection {
        let meeting = currentMeeting(in: context, now: now)
        let connection = Connection(fullName: fullName.trimmingCharacters(in: .whitespacesAndNewlines),
                                    jobTitle: jobTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                                    company: company.trimmingCharacters(in: .whitespacesAndNewlines),
                                    source: source, context: meeting.context)
        for field in fields where !field.isEmpty {
            connection.setValue(field.value.trimmingCharacters(in: .whitespacesAndNewlines), for: field.kind)
        }
        context.insert(connection)
        connection.event = meeting.event
        return connection
    }

    /// Last 9 digits — "+998 90 123 45 67" and "90 123-45-67" are the same number.
    private static func phoneKey(_ value: String) -> String {
        String(PhoneFormat.digits(value).suffix(9))
    }
}

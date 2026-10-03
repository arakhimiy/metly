import Foundation
import MetlyCore
import MetlyData
import SwiftData

/// Everything the Context Capture block edits. A plain value: bind it to `ContextCaptureForm`
/// and commit it with `apply(to:in:limits:)` when the user taps Save.
public struct CaptureDraft: Equatable, Sendable {
    /// How `apply` merges the draft into the connection.
    public enum Intent: Sendable {
        /// Same meeting (first capture or an edit): context, note and tags are replaced.
        case editContext
        /// The owner met a known person again: the previous meeting moves to "Earlier Meetings"
        /// when the event differs, the note is appended and tags are merged.
        case newMeeting
    }

    /// The values that were filled in automatically (active event, the connection's stamp or location).
    public struct AutoFill: Equatable, Sendable {
        public var eventName: String
        public var place: String
        public var city: String

        public init(eventName: String, place: String, city: String) {
            self.eventName = eventName
            self.place = place
            self.city = city
        }
    }

    public var intent: Intent

    // Where You Met
    /// Linked `Event` record; kept by `apply` only while `eventName` still equals that event's name.
    public var eventID: UUID?
    public var eventName: String
    public var place: String
    public var city: String
    public var metAt: Date
    public var autoFill: AutoFill?

    // Private note
    public var note: String
    public var tags: [String]

    // Follow up
    public var followUp: FollowUpDraft?
    /// Channel preselected when a quick pick is chosen (Telegram › Email › Call, by available fields).
    public var preferredChannel: FollowUpChannel
    /// The person's current open reminder, if any. Picking a day reschedules it instead of adding one.
    public var existingReminder: ReminderSummary?

    public init(intent: Intent = .editContext,
                context: MeetingContext = MeetingContext(),
                note: String = "",
                tags: [String] = [],
                preferredChannel: FollowUpChannel = .telegram,
                existingReminder: ReminderSummary? = nil) {
        self.intent = intent
        self.eventID = context.eventID
        self.eventName = context.eventName ?? ""
        self.place = context.place ?? ""
        self.city = context.city ?? ""
        self.metAt = context.metAt
        self.note = note
        self.tags = tags
        self.preferredChannel = preferredChannel
        self.existingReminder = existingReminder
    }

    /// True while the Where-You-Met fields still hold the automatically filled values ("Auto" badge).
    public var isAutoFilled: Bool {
        guard let autoFill else { return false }
        let hasValue = !(autoFill.eventName.isEmpty && autoFill.place.isEmpty && autoFill.city.isEmpty)
        return hasValue && autoFill.eventName == eventName && autoFill.place == place && autoFill.city == city
    }

    /// Marks the current Where-You-Met values as automatic.
    public mutating func markAutoFilled() {
        autoFill = AutoFill(eventName: eventName, place: place, city: city)
    }

    /// The meeting context the draft describes ("Place, City" typed into Place is split).
    public var meetingContext: MeetingContext {
        let event = eventName.trimmed
        var place = place.trimmed
        var city = city.trimmed
        if city.isEmpty, let comma = place.lastIndex(of: ",") {
            city = String(place[place.index(after: comma)...]).trimmed
            place = String(place[..<comma]).trimmed
        }
        return MeetingContext(eventID: event.isEmpty ? nil : eventID,
                              eventName: event.isEmpty ? nil : event,
                              place: place.isEmpty ? nil : place,
                              city: city.isEmpty ? nil : city,
                              metAt: metAt)
    }
}

// MARK: - Factories

public extension CaptureDraft {
    /// Capture for the meeting that just happened (CONNECTED, PAPER_REVIEW, ADD_CONTEXT, JUST_MET).
    /// Starts from the connection's stamped context, falling back to the active event; marks it "Auto".
    /// Place stays empty when unknown so the form can fill it from the current location.
    static func capture(for connection: Connection?, in modelContext: ModelContext, now: Date = .now) -> CaptureDraft {
        let stamped = connection?.context
        let hasStamp = stamped.map { ($0.eventName ?? "").isEmpty == false || ($0.place ?? "").isEmpty == false } ?? false
        let context: MeetingContext
        if let stamped, hasStamp {
            context = MeetingContext(eventID: stamped.eventID ?? connection?.event?.id, eventName: stamped.eventName,
                                     place: stamped.place, city: stamped.city, metAt: stamped.metAt)
        } else {
            context = activeEventContext(in: modelContext, metAt: stamped?.metAt ?? now)
        }
        var draft = CaptureDraft(intent: .editContext, context: context,
                                 note: connection?.note ?? "", tags: connection?.tags ?? [],
                                 preferredChannel: FollowUpPolicy.preferredChannel(for: connection),
                                 existingReminder: connection.flatMap(Self.reminderSummary))
        draft.markAutoFilled()
        return draft
    }

    /// The owner met someone they already know again (e.g. scanned at another event).
    /// Context comes from the active event (or location), note and tags start empty.
    static func newMeeting(with connection: Connection, in modelContext: ModelContext, now: Date = .now) -> CaptureDraft {
        var draft = CaptureDraft(intent: .newMeeting, context: activeEventContext(in: modelContext, metAt: now),
                                 preferredChannel: FollowUpPolicy.preferredChannel(for: connection),
                                 existingReminder: reminderSummary(for: connection))
        draft.markAutoFilled()
        return draft
    }

    /// Edit a connection's existing context, note and tags (no "Auto" badge).
    init(editing connection: Connection) {
        var context = connection.context
        if context.eventID == nil { context.eventID = connection.event?.id }
        self.init(intent: .editContext, context: context, note: connection.note, tags: connection.tags,
                  preferredChannel: FollowUpPolicy.preferredChannel(for: connection),
                  existingReminder: Self.reminderSummary(for: connection))
    }

    private static func activeEventContext(in modelContext: ModelContext, metAt: Date) -> MeetingContext {
        guard let event = modelContext.activeEvent() else { return MeetingContext(metAt: metAt) }
        return MeetingContext(eventID: event.id, eventName: event.name,
                              place: event.place.isEmpty ? nil : event.place,
                              city: event.city.isEmpty ? nil : event.city, metAt: metAt)
    }

    private static func reminderSummary(for connection: Connection) -> ReminderSummary? {
        connection.openFollowUp.map { ReminderSummary(title: $0.title, dueAt: $0.dueAt, channel: $0.channel) }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

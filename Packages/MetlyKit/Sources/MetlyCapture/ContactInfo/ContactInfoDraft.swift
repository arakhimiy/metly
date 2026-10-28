import Foundation
import MetlyCore
import MetlyData
import MetlyDesign

/// A person's contact list while it's edited (schema 3.0.0): phones with their label, email, Telegram,
/// WhatsApp, Instagram, website, LinkedIn — any mix, in order. Bind it to `ContactInfoEditor`, commit with
/// `apply(to:)`.
public struct ContactInfoDraft: Equatable, Sendable {
    /// May hold an empty row while editing (dropped on apply).
    public var entries: [ContactEntry]

    public init(entries: [ContactEntry] = []) {
        self.entries = entries
    }

    public init(connection: Connection) {
        self.init(entries: connection.contacts.filter { !$0.isEmpty })
    }

    /// Whether "+ Add Contact" is offered.
    public var canAdd: Bool { entries.count < ContactEntry.maxCount }

    /// Adds an empty row of `kind` and returns its id (to focus it). An empty row already there is reused
    /// instead of stacking another one; nil at the limit.
    @discardableResult
    public mutating func add(_ kind: ContactFieldKind) -> UUID? {
        if let index = entries.firstIndex(where: \.isEmpty) {
            if entries[index].kind != kind { entries[index] = ContactEntry(id: entries[index].id, kind: kind, label: nextPhoneLabel) }
            return entries[index].id
        }
        guard canAdd else { return nil }
        let entry = ContactEntry(kind: kind, label: kind == .phone ? nextPhoneLabel : nil, privacy: .connections)
        entries.append(entry)
        return entry.id
    }

    /// Label for the next added number: the first of Mobile, Work, Home not used yet, else Other.
    public var nextPhoneLabel: PhoneLabel {
        let used = Set(entries.filter { $0.kind == .phone }.compactMap(\.label))
        return PhoneLabel.allCases.first { !used.contains($0) } ?? .other
    }

    public mutating func remove(id: ContactEntry.ID) {
        entries.removeAll { $0.id == id }
    }

    public mutating func remove(atOffsets offsets: IndexSet) {
        entries = entries.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
    }

    /// The list as it'll be saved: values cleaned up ("@handle", single spaces), within the limits, empty
    /// rows dropped.
    public var savedEntries: [ContactEntry] {
        let cleaned = entries.compactMap { entry -> ContactEntry? in
            let value = String(ContactFieldInput.normalized(entry.value, for: entry.kind)
                .prefix(ContactEntry.maxLength(for: entry.kind))).trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { return nil }
            var saved = entry
            saved.value = value
            return saved
        }
        return Array(cleaned.prefix(ContactEntry.maxCount))
    }

    /// Follow-up channel these values suggest (Telegram by username or mobile number › Email › Call).
    public var preferredChannel: FollowUpChannel {
        let saved = savedEntries
        let phones = saved.filter { $0.kind == .phone }
        let ordered = phones.filter { $0.label == .mobile } + phones.filter { $0.label != .mobile }
        return FollowUpPolicy.preferredChannel(phones: ordered.map(\.value), email: saved.first(of: .email)?.value ?? "",
                                               telegram: saved.first(of: .telegram)?.value ?? "")
    }

    /// Writes the list into `connection` and marks it changed when anything differs. Doesn't save.
    /// Returns whether it changed.
    @discardableResult
    public func apply(to connection: Connection) -> Bool {
        let saved = savedEntries
        guard connection.contacts.filter({ !$0.isEmpty }) != saved else { return false }
        connection.contacts = saved
        connection.markChanged()
        return true
    }
}

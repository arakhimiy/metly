import Foundation
import MetlyCore

// Editing the owner's contact list (schema 3.0.0): "+ Add Contact" in PROFILE › Contact Details and in a
// card's "Show on This Card". An entry being typed lives in `contacts` with an empty value; empty entries
// are never synced (`trimmedForSync`) and go away when the user leaves them (`removeEmptyContacts`).

public extension Profile {
    /// Room for another entry (empty ones being typed count, so the list never grows past the limit).
    var canAddContact: Bool { contacts.count < ContactEntry.maxCount }

    /// Adds an empty entry of `kind` for the user to type into and returns its id. When an entry is already
    /// empty, that one is reused (switched to `kind`) instead of adding a second blank row — tapping
    /// "+ Add Contact" twice must not stack empty rows. Nil when the list is full.
    @discardableResult
    func addContact(_ kind: ContactFieldKind) -> UUID? {
        if let index = contacts.firstIndex(where: \.isEmpty) {
            if contacts[index].kind != kind {
                contacts[index] = ContactEntry(id: contacts[index].id, kind: kind,
                                               label: kind == .phone ? Self.suggestedPhoneLabel(in: contacts) : nil,
                                               privacy: Self.suggestedPrivacy(for: kind, in: contacts))
            }
            return contacts[index].id
        }
        guard canAddContact else { return nil }
        let entry = ContactEntry(kind: kind, label: kind == .phone ? Self.suggestedPhoneLabel(in: contacts) : nil,
                                 privacy: Self.suggestedPrivacy(for: kind, in: contacts))
        contacts.append(entry)
        return entry.id
    }

    /// Label for a new number: the first of Mobile, Work, Home not used yet (like Contacts), else Other.
    static func suggestedPhoneLabel(in contacts: [ContactEntry]) -> PhoneLabel {
        let used = Set(contacts.filter { $0.kind == .phone && !$0.isEmpty }.compactMap(\.label))
        return [PhoneLabel.mobile, .work, .home].first { !used.contains($0) } ?? .other
    }

    /// Edits one entry; queues the profile for sync when a non-empty value changed.
    func updateContact(id: UUID, _ change: (inout ContactEntry) -> Void) {
        guard let index = contacts.firstIndex(where: { $0.id == id }) else { return }
        var entry = contacts[index]
        change(&entry)
        entry.value = String(entry.value.prefix(ContactEntry.maxLength(for: entry.kind)))
        guard entry != contacts[index] else { return }
        let wasSynced = !contacts[index].isEmpty
        contacts[index] = entry
        if wasSynced || !entry.isEmpty { markChanged() }
    }

    func removeContacts(ids: Set<UUID>) {
        let removedFilled = contacts.contains { ids.contains($0.id) && !$0.isEmpty }
        contacts.removeAll { ids.contains($0.id) }
        if removedFilled { markChanged() }
    }

    func moveContacts(fromOffsets source: IndexSet, toOffset destination: Int) {
        contacts.move(fromOffsets: source, toOffset: destination)
        markChanged()
    }

    /// Drops entries left empty (an "+ Add Contact" row the user walked away from).
    func removeEmptyContacts() {
        if contacts.contains(where: \.isEmpty) { contacts.removeAll(where: \.isEmpty) }
    }

    /// A new number starts at Connections — Private when the user's phones are all Private, so adding one
    /// never shares more than they chose. Other kinds take their default.
    static func suggestedPrivacy(for kind: ContactFieldKind, in contacts: [ContactEntry]) -> FieldPrivacy {
        guard kind.isPhoneNumber else { return kind.defaultPrivacy }
        let numbers = contacts.filter { $0.kind.isPhoneNumber && !$0.isEmpty }
        return !numbers.isEmpty && numbers.allSatisfy { $0.privacy == .private } ? .private : kind.defaultPrivacy
    }

    /// Entries a card shows before the audience filter, in the profile's order: `ids` when set, else (a card
    /// from before 3.0.0) the entries whose kind is in `design.visibleFields`.
    func contacts(selectedBy ids: [UUID]?, design: CardDesign) -> [ContactEntry] {
        let live = contacts.filter { !$0.isEmpty }
        guard let ids else { return live.filter { design.visibleFields.contains($0.kind) } }
        let chosen = Set(ids)
        return live.filter { chosen.contains($0.id) }
    }

    /// What a new card shows: every entry that isn't Private.
    var defaultCardSelection: [UUID] {
        contacts.filter { !$0.isEmpty && $0.privacy != .private }.map(\.id)
    }
}

public extension CardDesign {
    /// Keeps `visibleFields` (older apps, the server's legacy view) in step with a selection of entries.
    mutating func syncVisibleFields(with ids: [UUID], in contacts: [ContactEntry]) {
        let kinds = Set(contacts.filter { ids.contains($0.id) && !$0.isEmpty }.map(\.kind))
        visibleFields = Set(ContactFieldKind.legacy.filter(kinds.contains))
    }
}

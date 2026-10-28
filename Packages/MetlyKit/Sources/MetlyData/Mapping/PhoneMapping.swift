import Foundation
import MetlyCore
import MetlyNetworking

// Copying someone's contact entries onto a Connection. `CardSnapshot` (and so `theirCard`) carries the
// legacy one-per-kind fields only, so flows that build a connection from a card copy the list here. The
// server does the same when a connect request is accepted.

public extension Connection {
    /// Appends entries not here yet (same kind and value; phone numbers compare by digits) while there is
    /// room — never overwriting a value already saved; a number already here takes their label
    /// (`[ContactEntry].merge`).
    /// - Returns: whether anything changed. On an existing record, call `markChanged()` when true.
    @discardableResult
    func mergeContacts(_ incoming: [ContactEntry], adoptsLabels: Bool = true) -> Bool {
        var list = contacts
        guard list.merge(incoming, adoptsLabels: adoptsLabels) else { return false }
        contacts = list
        return true
    }

    /// SCANNED_CARD "Add to People" / offline connect: every entry the public card shows.
    @discardableResult
    func mergePhones(from card: PublicCardDTO) -> Bool {
        mergeContacts(card.contacts)
    }

    /// Same, from loose values (PAPER_REVIEW `PaperCardDraft.phoneLabel/additionalPhones`, a vCard…): the
    /// first number keeps `label`, every number is kept — as many as the card has, up to the list limit.
    @discardableResult
    func mergePhones(primary: String, label: PhoneLabel, additional: [LabeledPhone]) -> Bool {
        var incoming = additional.map { ContactEntry(id: $0.id, kind: .phone, label: $0.label, value: $0.value) }
        if !primary.trimmingCharacters(in: .whitespaces).isEmpty {
            incoming.insert(ContactEntry(kind: .phone, label: label, value: primary), at: 0)
        }
        return mergeContacts(incoming)
    }
}

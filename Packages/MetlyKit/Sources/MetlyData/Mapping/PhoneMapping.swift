import Foundation
import MetlyCore
import MetlyNetworking

// Copying someone's labelled phones onto a Connection (schema 2.0.0). `CardSnapshot` (and so
// `theirCard`) carries no extra phones, so flows that build a connection from a card copy them here.
// The server does the same when a connect request is accepted.

public extension Connection {
    /// SCANNED_CARD "Add to People" / offline connect: the public card's phone label and extra phones.
    /// Fills gaps only (see `PhoneMerge.merge`); call after `phone` was set from the card's fields.
    /// - Returns: whether anything changed. On an existing record, call `markChanged()` when true.
    @discardableResult
    func mergePhones(from card: PublicCardDTO) -> Bool {
        let primary = card.fields.first { $0.kind == .phone }?.value ?? ""
        return mergePhones(primary: primary, label: card.phoneLabel, additional: card.additionalPhones)
    }

    /// Same, from loose values (PAPER_REVIEW `PaperCardDraft.phoneLabel/additionalPhones`, a vCard…).
    @discardableResult
    func mergePhones(primary: String, label: PhoneLabel, additional: [LabeledPhone]) -> Bool {
        var phone = phone
        var phoneLabel = phoneLabel
        var additionalPhones = additionalPhones
        guard PhoneMerge.merge(phone: &phone, label: &phoneLabel, additional: &additionalPhones,
                               incomingPhone: primary, incomingLabel: label, incomingAdditional: additional) else { return false }
        self.phone = phone
        self.phoneLabel = phoneLabel
        self.additionalPhones = additionalPhones
        return true
    }
}

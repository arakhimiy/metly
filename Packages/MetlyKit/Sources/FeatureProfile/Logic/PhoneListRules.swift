import Foundation
import MetlyCore
import MetlyDesign

/// Rules for the owner's extra phone numbers (PROFILE › Contact Details). Pure, unit-tested.
nonisolated enum PhoneListRules {
    static func canAdd(to phones: [LabeledPhone]) -> Bool {
        phones.count < ProfileFieldLimits.maxAdditionalPhones
    }

    /// Label for a new number: the first of Mobile, Work, Home not used yet (like Contacts), else Other.
    static func suggestedLabel(primary: PhoneLabel, extras: [LabeledPhone]) -> PhoneLabel {
        let used = Set([primary] + extras.map(\.label))
        return [PhoneLabel.mobile, .work, .home].first { !used.contains($0) } ?? .other
    }

    /// Privacy for a new number: phones start at Connections, but a Private primary phone keeps new
    /// numbers Private too — adding a number never shares more than the user chose for their phone.
    static func suggestedPrivacy(primary: FieldPrivacy) -> FieldPrivacy {
        primary == .private ? .private : ContactFieldKind.phone.defaultPrivacy
    }

    static func newPhone(primaryLabel: PhoneLabel, primaryPrivacy: FieldPrivacy, extras: [LabeledPhone]) -> LabeledPhone {
        LabeledPhone(label: suggestedLabel(primary: primaryLabel, extras: extras), value: "",
                     privacy: suggestedPrivacy(primary: primaryPrivacy))
    }

    /// A number as typed, capped at the server limit.
    static func capped(_ value: String) -> String {
        ProfileFieldLimits.capped(value, at: ProfileFieldLimits.phone)
    }

    /// Cleaned up when the user leaves the field (spaces collapsed, trimmed, capped).
    static func normalized(_ value: String) -> String {
        capped(ContactFieldInput.normalized(value, for: .phone))
    }
}

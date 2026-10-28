import Foundation
import MetlyCore
import MetlyData
import MetlyDesign

/// A person's contact values while they're edited: every phone with its label (primary first) plus
/// email, Telegram, website and LinkedIn. Bind it to `ContactInfoEditor`, commit with `apply(to:)`.
public struct ContactInfoDraft: Equatable, Sendable {
    /// Primary first; may hold empty rows while editing (dropped on apply).
    public var phones: [LabeledPhone]
    public var email: String
    public var telegram: String
    public var website: String
    public var linkedin: String

    public init(phones: [LabeledPhone] = [], email: String = "", telegram: String = "", website: String = "",
                linkedin: String = "") {
        self.phones = phones
        self.email = email
        self.telegram = telegram
        self.website = website
        self.linkedin = linkedin
    }

    public init(connection: Connection) {
        self.init(phones: connection.allPhones, email: connection.email, telegram: connection.telegram,
                  website: connection.website, linkedin: connection.linkedin)
    }

    /// Label for the next added number: the first of Mobile, Work, Home not used yet, else Other.
    public var nextPhoneLabel: PhoneLabel {
        let used = Set(phones.map(\.label))
        return PhoneLabel.allCases.first { !used.contains($0) } ?? .other
    }

    /// Adds an empty number row and returns its id (to focus it).
    @discardableResult
    public mutating func addPhone() -> UUID {
        let phone = LabeledPhone(label: nextPhoneLabel)
        phones.append(phone)
        return phone.id
    }

    public mutating func removePhone(id: LabeledPhone.ID) {
        phones.removeAll { $0.id == id }
    }

    public mutating func removePhones(atOffsets offsets: IndexSet) {
        phones = phones.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
    }

    /// Cleaned phones as they'll be saved: trimmed, single spaces, empty rows dropped.
    public var savedPhones: [LabeledPhone] {
        phones.compactMap { phone in
            let value = ContactFieldInput.normalized(phone.value, for: .phone)
            guard !value.isEmpty else { return nil }
            var cleaned = phone
            cleaned.value = value
            return cleaned
        }
    }

    /// Follow-up channel these values suggest (Telegram by username or mobile number › Email › Call).
    public var preferredChannel: FollowUpChannel {
        let saved = savedPhones
        let ordered = saved.filter { $0.label == .mobile } + saved.filter { $0.label != .mobile }
        return FollowUpPolicy.preferredChannel(phones: ordered.map(\.value), email: email, telegram: telegram)
    }

    /// Writes the values into `connection` (first phone → `phone` + `phoneLabel`, the rest →
    /// `additionalPhones`) and marks it changed when anything differs. Doesn't save. Returns whether it changed.
    @discardableResult
    public func apply(to connection: Connection) -> Bool {
        let saved = savedPhones
        let primary = saved.first
        let additional = saved.dropFirst().map { phone in
            // The primary's stable id must never be stored on an extra number.
            phone.isPrimary ? LabeledPhone(label: phone.label, value: phone.value, privacy: phone.privacy) : phone
        }
        let values: [ContactFieldKind: String] = [
            .email: ContactFieldInput.normalized(email, for: .email),
            .telegram: ContactFieldInput.normalized(telegram, for: .telegram),
            .website: ContactFieldInput.normalized(website, for: .website),
            .linkedin: ContactFieldInput.normalized(linkedin, for: .linkedin),
        ]

        var changed = false
        if connection.phone != (primary?.value ?? "") {
            connection.phone = primary?.value ?? ""
            changed = true
        }
        let label = primary?.label ?? .mobile
        if connection.phoneLabel != label {
            connection.phoneLabel = label
            changed = true
        }
        if connection.additionalPhones != Array(additional) {
            connection.additionalPhones = Array(additional)
            changed = true
        }
        for (kind, value) in values where connection.value(for: kind) != value {
            connection.setValue(value, for: kind)
            changed = true
        }
        if changed { connection.markChanged() }
        return changed
    }
}

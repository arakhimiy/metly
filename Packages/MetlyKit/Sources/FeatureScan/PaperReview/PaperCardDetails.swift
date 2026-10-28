import Foundation
import MetlyCardKit
import MetlyCore

/// One phone number row on PAPER_REVIEW.
struct PaperPhoneRow: Identifiable, Equatable {
    var id = UUID()
    var label: PhoneLabel
    var value: String

    var isEmpty: Bool { value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// The editable values on PAPER_REVIEW, plus the "Use As" / "Swap" moves of its Recognized Text.
struct PaperCardDetails: Equatable {
    var fullName: String
    var jobTitle: String
    var company: String
    /// Every number on the card, in the order shown.
    var phones: [PaperPhoneRow]
    var email: String
    var telegram: String
    var website: String
    var linkedin: String

    init(draft: PaperCardDraft) {
        fullName = draft.fullName
        jobTitle = draft.jobTitle
        company = draft.company
        let primary = draft.value(for: .phone)
        phones = (primary.isEmpty ? [] : [PaperPhoneRow(label: draft.phoneLabel, value: primary)])
            + draft.additionalPhones.filter { !$0.isEmpty }.map { PaperPhoneRow(label: $0.label, value: $0.value) }
        email = draft.value(for: .email)
        telegram = draft.value(for: .telegram)
        website = draft.value(for: .website)
        linkedin = draft.value(for: .linkedin)
    }

    /// Text fields by row; `.phone` is the first phone row.
    subscript(field: PaperField) -> String {
        get {
            switch field {
            case .name: fullName
            case .title: jobTitle
            case .company: company
            case .phone: phones.first?.value ?? ""
            case .email: email
            case .telegram: telegram
            case .website: website
            case .linkedin: linkedin
            }
        }
        set {
            switch field {
            case .name: fullName = newValue
            case .title: jobTitle = newValue
            case .company: company = newValue
            case .phone:
                if phones.isEmpty { phones.append(PaperPhoneRow(label: .mobile, value: newValue)) } else { phones[0].value = newValue }
            case .email: email = newValue
            case .telegram: telegram = newValue
            case .website: website = newValue
            case .linkedin: linkedin = newValue
            }
        }
    }

    /// A connection needs a name.
    var canSave: Bool {
        !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Saving

    /// The first mobile number is the primary phone (`connection.phone`); the others, in order,
    /// become `additionalPhones`. Empty rows are skipped.
    var savedPhones: (primary: PaperPhoneRow?, additional: [PaperPhoneRow]) {
        let filled = phones.filter { !$0.isEmpty }.map { row in
            var trimmed = row
            trimmed.value = row.value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed
        }
        guard let primary = filled.firstIndex(where: { $0.label == .mobile }) ?? filled.indices.first else { return (nil, []) }
        var others = filled
        let first = others.remove(at: primary)
        return (first, others)
    }

    /// Non-empty contact values, trimmed, in display order (the primary phone only).
    var contactFields: [ContactField] {
        ContactFieldKind.allCases.compactMap { kind in
            let value = kind == .phone ? (savedPhones.primary?.value ?? "")
                : self[PaperField(kind: kind)].trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : ContactField(kind: kind, value: value)
        }
    }

    var draft: PaperCardDraft {
        let phones = savedPhones
        return PaperCardDraft(fullName: fullName.trimmingCharacters(in: .whitespacesAndNewlines),
                              jobTitle: jobTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                              company: company.trimmingCharacters(in: .whitespacesAndNewlines),
                              fields: contactFields,
                              phoneLabel: phones.primary?.label ?? .mobile,
                              additionalPhones: phones.additional.map { LabeledPhone(label: $0.label, value: $0.value) })
    }

    // MARK: Phones

    /// Adds an empty row (Mobile if there is no mobile yet, else Work) and returns its id.
    @discardableResult
    mutating func addPhone() -> PaperPhoneRow.ID {
        let row = PaperPhoneRow(label: phones.contains { $0.label == .mobile } ? .work : .mobile, value: "")
        phones.append(row)
        return row.id
    }

    mutating func removePhones(at offsets: IndexSet) {
        phones.remove(atOffsets: offsets)
    }

    // MARK: Name ⇄ company

    var canSwapNameAndCompany: Bool {
        !fullName.trimmingCharacters(in: .whitespaces).isEmpty && !company.trimmingCharacters(in: .whitespaces).isEmpty
    }

    mutating func swapNameAndCompany() {
        (fullName, company) = (company, fullName)
    }

    // MARK: Recognized text

    /// Which fields currently hold (part of) `line`.
    func uses(of line: String) -> [PaperLineUse] {
        let reading = PaperLineReading(line)
        var uses: [PaperLineUse] = []
        for field in PaperRoles.fields {
            let value = self[field]
            if !value.isEmpty, !reading.leftover.isEmpty, PaperRoleClassifier.overlaps(value, reading.leftover) {
                uses.append(PaperLineUse(field: field))
            }
        }
        if phones.contains(where: { !$0.isEmpty && reading.phoneKeys.contains(PhoneFormat.key($0.value)) }) { uses.append(.phone) }
        if reading.matches(email, parsed: reading.contacts.emails) { uses.append(.email) }
        if reading.matches(website, parsed: reading.contacts.websites) { uses.append(.website) }
        let username = ContactValueFormat.telegramUsername(from: telegram) ?? telegram
        if reading.matches(username, parsed: reading.contacts.telegrams) { uses.append(.telegram) }
        if reading.matches(linkedin, parsed: reading.contacts.linkedins) { uses.append(.linkedin) }
        return uses
    }

    /// Uses `line` for `use`: the value is taken from the line (a phone number, an address, the
    /// name half of "Name, Title"…), and any other field that held that text lets go of it
    /// (the other half of "Name, Title" keeps its field). `.ignore` only lets go.
    mutating func use(_ line: String, as use: PaperLineUse) {
        let reading = PaperLineReading(line)
        let current = uses(of: line).filter { $0 != use }
        switch use {
        case .name, .title, .company:
            let value = switch use {
            case .name: PaperText.titleCasedIfAllCaps(reading.part(forTitle: false))
            case .title: PaperText.titleCasedIfAllCaps(reading.part(forTitle: true))
            default: reading.part(forTitle: false)
            }
            for other in current {
                if let field = other.field, PaperRoles.fields.contains(field) {
                    if PaperRoleClassifier.overlaps(self[field], value) { self[field] = "" }
                } else {
                    clear(other, reading: reading)
                }
            }
            if let field = use.field { self[field] = value }
            return
        default:
            for other in current { clear(other, reading: reading) }
        }
        switch use {
        case .ignore, .name, .title, .company:
            break
        case .phone:
            let found = reading.contacts.phones.first
            let value = found?.value ?? reading.cleaned
            guard !phones.contains(where: { PhoneFormat.key($0.value) == PhoneFormat.key(value) && !$0.isEmpty }) else { return }
            if let empty = phones.firstIndex(where: \.isEmpty) {
                phones[empty].value = value
                if let found { phones[empty].label = found.label }
            } else {
                phones.append(PaperPhoneRow(label: found?.label ?? .mobile, value: value))
            }
        case .email:
            email = reading.contacts.emails.first ?? reading.cleaned
        case .website:
            website = reading.contacts.websites.first ?? reading.cleaned
        case .telegram:
            telegram = reading.contacts.telegrams.first.map { ContactValueFormat.telegramDisplay(username: $0) } ?? reading.cleaned
        case .linkedin:
            linkedin = reading.contacts.linkedins.first ?? reading.cleaned
        }
    }

    private mutating func clear(_ use: PaperLineUse, reading: PaperLineReading) {
        switch use {
        case .phone: phones.removeAll { reading.phoneKeys.contains(PhoneFormat.key($0.value)) }
        case .ignore: break
        default: if let field = use.field { self[field] = "" }
        }
    }
}

/// One recognized line read the way the parser reads it: its contact values and the leftover text.
private struct PaperLineReading {
    let cleaned: String
    let leftover: String
    let contacts: PaperContacts

    init(_ line: String) {
        cleaned = PaperText.cleanLeftover(line)
        var contacts = PaperContacts()
        leftover = PaperText.cleanLeftover(PaperContactExtractor().extract(from: line, into: &contacts))
        self.contacts = contacts
    }

    var phoneKeys: Set<String> { Set(contacts.phones.map { PhoneFormat.key($0.value) }) }

    /// "Aziza Karimova, Product Designer" → the title half or the other one; otherwise the whole leftover.
    func part(forTitle: Bool) -> String {
        let text = leftover.isEmpty ? cleaned : leftover
        let parts = PaperRoleClassifier.split(RoleCandidate(text: text, index: 0, height: 0))
        guard parts.count == 2 else { return text }
        return parts.first { (RoleEvidence.titleScore($0.text) > 0) == forTitle }?.text ?? text
    }

    /// The field's value was parsed from this line, or is this line as typed.
    func matches(_ value: String, parsed: [String]) -> Bool {
        let value = value.trimmingCharacters(in: .whitespaces).lowercased()
        guard !value.isEmpty else { return false }
        return parsed.contains { $0.lowercased() == value } || PaperText.comparable(value) == PaperText.comparable(cleaned)
    }
}

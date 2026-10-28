import Foundation
import MetlyCore

/// Everything a template renders, resolved from `CardDesign` + `CardFaceContent` (SPEC Appendix B).
/// Pure value logic — unit-tested independently from layout.
public struct CardFaceModel: Hashable, Sendable {
    public struct Contact: Hashable, Sendable, Identifiable {
        public let kind: ContactFieldKind
        public let value: String
        /// Set on phone lines when the card shows more than one number, so they can be told apart.
        public let phoneLabel: PhoneLabel?
        public let id: String

        init(kind: ContactFieldKind, value: String, phoneLabel: PhoneLabel? = nil, id: String? = nil) {
            self.kind = kind
            self.value = value
            self.phoneLabel = phoneLabel
            self.id = id ?? kind.rawValue
        }

        /// Terminal template key: `tel`, `tel.work`, `mail`…
        public var terminalKey: String { phoneLabel?.terminalKey ?? kind.terminalKey }

        /// What VoiceOver says before the value: "Work phone", "Email".
        public var spokenTitle: String { phoneLabel?.phoneNumberTitle ?? kind.title }

        func labelled(_ label: PhoneLabel?) -> Contact {
            Contact(kind: kind, value: value, phoneLabel: label, id: id)
        }
    }

    /// Contact lines after the density limit, plus what it left out (CARD_EDITOR notes).
    public struct ContactLines: Hashable, Sendable {
        public let shown: [Contact]
        /// One-per-kind lines (phone, email, …) the density limit cuts off.
        public let hiddenFieldCount: Int
        /// Extra phone numbers that don't fit: they only use lines left free after one line per kind.
        public let hiddenPhoneCount: Int
    }

    public let fullName: String
    public let firstName: String
    public let lastName: String
    public let jobTitle: String
    public let company: String
    public let role: String
    public let initials: String
    public let monogram: String
    /// Visible, non-private, non-empty contacts in display order, truncated to the density limit.
    public let contacts: [Contact]
    /// Bold shows only two contact values (same rules with a limit of two).
    public let boldContacts: [Contact]
    public let photoData: Data?
    public let logoData: Data?
    public let showsQR: Bool
    public let qrPayload: String

    public init(design: CardDesign, content: CardFaceContent) {
        let name = content.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = name.split(whereSeparator: \.isWhitespace).map(String.init)
        fullName = name.isEmpty ? String(localized: "Your Name") : name
        firstName = words.first ?? fullName
        lastName = words.dropFirst().joined(separator: " ")
        jobTitle = content.jobTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        company = content.company.trimmingCharacters(in: .whitespacesAndNewlines)
        role = [jobTitle, company].filter { !$0.isEmpty }.joined(separator: " · ")

        let nameInitials = words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        initials = nameInitials.isEmpty ? (company.first.map { String($0).uppercased() } ?? "?") : nameInitials
        monogram = company.first.map { String($0).uppercased() } ?? String(initials.prefix(1))

        let candidates = Self.candidates(fields: content.fields, additionalPhones: content.additionalPhones,
                                         phoneLabel: content.phoneLabel, design: design)
        contacts = Self.allocate(candidates, limit: design.density.maxContacts).shown
        boldContacts = Self.allocate(candidates, limit: min(2, design.density.maxContacts)).shown
        photoData = design.showPhoto ? content.photoData : nil
        logoData = design.showLogo ? content.logoData : nil
        showsQR = design.showQR
        let payload = content.qrPayload.trimmingCharacters(in: .whitespacesAndNewlines)
        qrPayload = payload.isEmpty ? "https://\(Brand.linkHost)" : payload
    }

    /// The contacts list rule: design-visible, non-empty, never Private, fixed display order (phone, email,
    /// telegram, website, linkedin), density limit. Phones are grouped: the primary number first, then the
    /// extra ones — but extras only take lines left free after one line per kind, so a second number never
    /// pushes the email or Telegram off the card.
    public static func contacts(from fields: [ContactField], additionalPhones: [LabeledPhone] = [],
                                phoneLabel: PhoneLabel = .mobile, design: CardDesign) -> [Contact] {
        contactLines(from: fields, additionalPhones: additionalPhones, phoneLabel: phoneLabel, design: design).shown
    }

    /// `contacts(from:…)` plus how many lines the density limit left out.
    public static func contactLines(from fields: [ContactField], additionalPhones: [LabeledPhone] = [],
                                    phoneLabel: PhoneLabel = .mobile, design: CardDesign) -> ContactLines {
        allocate(candidates(fields: fields, additionalPhones: additionalPhones, phoneLabel: phoneLabel, design: design),
                 limit: design.density.maxContacts)
    }

    /// Every line the card could show, before the density limit.
    struct Candidates: Hashable, Sendable {
        /// Primary number first, then the extras (duplicates dropped).
        var phones: [Contact] = []
        /// One line per remaining kind, in display order.
        var others: [Contact] = []
    }

    static func candidates(fields: [ContactField], additionalPhones: [LabeledPhone], phoneLabel: PhoneLabel,
                           design: CardDesign) -> Candidates {
        var byKind: [ContactFieldKind: String] = [:]
        for field in fields where field.privacy != .private && design.visibleFields.contains(field.kind) {
            let value = singleLine(field.value)
            guard !value.isEmpty, byKind[field.kind] == nil else { continue }
            byKind[field.kind] = value
        }

        var result = Candidates()
        var seenNumbers = Set<String>()
        func addPhone(_ value: String, label: PhoneLabel, id: String) {
            let digits = value.filter(\.isNumber)
            if !digits.isEmpty {
                guard seenNumbers.insert(digits).inserted else { return }
            }
            result.phones.append(Contact(kind: .phone, value: value, phoneLabel: label, id: id))
        }
        if let primary = byKind[.phone] { addPhone(primary, label: phoneLabel, id: ContactFieldKind.phone.rawValue) }
        if design.visibleFields.contains(.phone) {
            for phone in additionalPhones where phone.privacy != .private {
                let value = singleLine(phone.value)
                guard !value.isEmpty else { continue }
                addPhone(value, label: phone.label, id: "phone.\(phone.id.uuidString)")
            }
        }
        result.others = ContactFieldKind.allCases.filter { $0 != .phone }.compactMap { kind in
            byKind[kind].map { Contact(kind: kind, value: $0) }
        }
        return result
    }

    /// Fills `limit` lines: one per kind first (the first phone stands for the phone kind), then the extra
    /// phones in the lines left over. Phone lines carry their label only when more than one is shown.
    static func allocate(_ candidates: Candidates, limit: Int) -> ContactLines {
        let limit = max(limit, 0)
        let perKind = Array(candidates.phones.prefix(1)) + candidates.others
        let base = Array(perKind.prefix(limit))
        let phoneLineShown = base.first?.kind == .phone
        let spare = limit - base.count
        let extras = phoneLineShown ? Array(candidates.phones.dropFirst().prefix(spare)) : []

        var phones = phoneLineShown ? [candidates.phones[0]] + extras : []
        let showsLabels = phones.count > 1
        phones = phones.map { $0.labelled(showsLabels ? $0.phoneLabel : nil) }

        return ContactLines(
            shown: phones + base.filter { $0.kind != .phone },
            hiddenFieldCount: perKind.count - base.count,
            hiddenPhoneCount: max(candidates.phones.count - 1, 0) - extras.count
        )
    }

    private static func singleLine(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).replacing("\n", with: " ")
    }

    /// Spoken description: name, role and every visible contact.
    public var accessibilityDescription: String {
        var parts = [fullName]
        let spokenRole = [jobTitle, company].filter { !$0.isEmpty }.joined(separator: ", ")
        if !spokenRole.isEmpty { parts.append(spokenRole) }
        parts += contacts.map { "\($0.spokenTitle): \($0.value)" }
        return parts.joined(separator: ". ")
    }
}

extension ContactFieldKind {
    /// Keys used by the Terminal template.
    var terminalKey: String {
        switch self {
        case .phone: "tel"
        case .email: "mail"
        case .telegram: "tg"
        case .website: "web"
        case .linkedin: "in"
        }
    }
}

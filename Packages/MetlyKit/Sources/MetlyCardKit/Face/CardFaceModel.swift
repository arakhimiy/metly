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
        /// Non-phone lines the density limit cuts off.
        public let hiddenFieldCount: Int
        /// Phone lines the density limit cuts off.
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

        let entries = content.isSelection ? content.contacts : content.contacts.filter { design.visibleFields.contains($0.kind) }
        let candidates = Self.candidates(entries)
        contacts = Self.allocate(candidates, limit: design.density.maxContacts).shown
        boldContacts = Self.allocate(candidates, limit: min(2, design.density.maxContacts)).shown
        photoData = design.showPhoto ? content.photoData : nil
        logoData = design.showLogo ? content.logoData : nil
        showsQR = design.showQR
        let payload = content.qrPayload.trimmingCharacters(in: .whitespacesAndNewlines)
        qrPayload = payload.isEmpty ? "https://\(Brand.linkHost)" : payload
    }

    /// The contacts list rule (3.0.0): the card's entries in the owner's order — `content.contacts` is
    /// already the card's selection for the audience — never Private or empty, a number shown once,
    /// cut at the density limit.
    public static func contacts(from entries: [ContactEntry], design: CardDesign) -> [Contact] {
        contactLines(from: entries, design: design).shown
    }

    /// `contacts(from:design:)` plus how many lines the density limit left out.
    public static func contactLines(from entries: [ContactEntry], design: CardDesign) -> ContactLines {
        allocate(candidates(entries), limit: design.density.maxContacts)
    }

    /// One-value-per-kind input (cards from before 3.0.0): the fields the design shows, then the extra phones.
    public static func contacts(from fields: [ContactField], additionalPhones: [LabeledPhone] = [],
                                phoneLabel: PhoneLabel = .mobile, design: CardDesign) -> [Contact] {
        let visible = fields.filter { design.visibleFields.contains($0.kind) }
        let phones = design.visibleFields.contains(.phone) ? additionalPhones : []
        return contacts(from: .fromLegacy(fields: visible, phoneLabel: phoneLabel, additionalPhones: phones,
                                          keeping: visible.filter { !$0.kind.isLegacy }.map { ContactEntry(kind: $0.kind, value: $0.value, privacy: $0.privacy) }),
                        design: design)
    }

    /// Every line the card could show, before the density limit.
    static func candidates(_ entries: [ContactEntry]) -> [Contact] {
        var result: [Contact] = []
        var seenNumbers = Set<String>()
        for entry in entries where entry.privacy != .private {
            let value = singleLine(entry.value)
            guard !value.isEmpty else { continue }
            if entry.kind == .phone {
                let digits = value.filter(\.isNumber)
                if !digits.isEmpty {
                    guard seenNumbers.insert(digits).inserted else { continue }
                }
            }
            result.append(Contact(kind: entry.kind, value: value, phoneLabel: entry.kind == .phone ? entry.label ?? .mobile : nil,
                                  id: entry.id.uuidString))
        }
        return result
    }

    /// The first `limit` lines. Phone lines carry their label only when more than one is shown.
    static func allocate(_ candidates: [Contact], limit: Int) -> ContactLines {
        let shown = Array(candidates.prefix(max(limit, 0)))
        let showsLabels = shown.filter { $0.kind == .phone }.count > 1
        let hidden = candidates.dropFirst(shown.count)
        return ContactLines(
            shown: shown.map { $0.kind == .phone ? $0.labelled(showsLabels ? $0.phoneLabel : nil) : $0 },
            hiddenFieldCount: hidden.filter { $0.kind != .phone }.count,
            hiddenPhoneCount: hidden.filter { $0.kind == .phone }.count
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
        case .whatsapp: "wa"
        case .instagram: "ig"
        }
    }
}

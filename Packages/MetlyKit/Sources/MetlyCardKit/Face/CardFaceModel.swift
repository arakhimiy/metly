import Foundation
import MetlyCore

/// Everything a template renders, resolved from `CardDesign` + `CardFaceContent` (SPEC Appendix B).
/// Pure value logic — unit-tested independently from layout.
public struct CardFaceModel: Hashable, Sendable {
    public struct Contact: Hashable, Sendable, Identifiable {
        public let kind: ContactFieldKind
        public let value: String
        public var id: ContactFieldKind { kind }
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

        contacts = Self.contacts(from: content.fields, design: design)
        photoData = design.showPhoto ? content.photoData : nil
        logoData = design.showLogo ? content.logoData : nil
        showsQR = design.showQR
        let payload = content.qrPayload.trimmingCharacters(in: .whitespacesAndNewlines)
        qrPayload = payload.isEmpty ? "https://\(Brand.linkHost)" : payload
    }

    /// The contacts list rule: design-visible, non-empty, never Private, one per kind,
    /// fixed display order (phone, email, telegram, website, linkedin), density limit.
    public static func contacts(from fields: [ContactField], design: CardDesign) -> [Contact] {
        var byKind: [ContactFieldKind: String] = [:]
        for field in fields where field.privacy != .private && design.visibleFields.contains(field.kind) {
            let value = field.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, byKind[field.kind] == nil else { continue }
            byKind[field.kind] = value.replacing("\n", with: " ")
        }
        let ordered = ContactFieldKind.allCases.compactMap { kind in byKind[kind].map { Contact(kind: kind, value: $0) } }
        return Array(ordered.prefix(design.density.maxContacts))
    }

    /// Bold shows only the first two contact values.
    public var boldContacts: [Contact] { Array(contacts.prefix(2)) }

    /// Spoken description: name, role and every visible contact.
    public var accessibilityDescription: String {
        var parts = [fullName]
        let spokenRole = [jobTitle, company].filter { !$0.isEmpty }.joined(separator: ", ")
        if !spokenRole.isEmpty { parts.append(spokenRole) }
        parts += contacts.map { "\($0.kind.title): \($0.value)" }
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

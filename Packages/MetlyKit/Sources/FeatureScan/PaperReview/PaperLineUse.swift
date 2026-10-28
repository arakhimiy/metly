import MetlyCore

/// What a recognized line of text can be used as ("Use As" on PAPER_REVIEW's Recognized Text).
nonisolated enum PaperLineUse: String, CaseIterable, Identifiable, Hashable, Sendable {
    case name, title, company, phone, email, website, telegram, linkedin, whatsapp, instagram, address, ignore

    var id: String { rawValue }

    var field: PaperField? {
        switch self {
        case .name: .name
        case .title: .title
        case .company: .company
        case .phone: .phone
        case .email: .email
        case .website: .website
        case .telegram: .telegram
        case .linkedin: .linkedin
        case .whatsapp: .whatsapp
        case .instagram: .instagram
        case .address: .address
        case .ignore: nil
        }
    }

    init(field: PaperField) {
        switch field {
        case .name: self = .name
        case .title: self = .title
        case .company: self = .company
        case .phone: self = .phone
        case .email: self = .email
        case .website: self = .website
        case .telegram: self = .telegram
        case .linkedin: self = .linkedin
        case .whatsapp: self = .whatsapp
        case .instagram: self = .instagram
        case .address: self = .address
        }
    }

    var title: String {
        switch self {
        case .name: String(localized: "Name")
        case .title: String(localized: "Job Title")
        case .company: String(localized: "Company")
        case .ignore: String(localized: "Ignore")
        default: field?.kind?.title ?? ""
        }
    }

    var symbolName: String {
        switch self {
        case .ignore: "nosign"
        default: field?.symbolName ?? "questionmark"
        }
    }
}

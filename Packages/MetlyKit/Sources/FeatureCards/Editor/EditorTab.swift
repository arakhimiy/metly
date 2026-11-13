/// CARD_EDITOR sections (templates v2): Template | Style | Details — three tabs, so every change is one tap
/// away. Style holds colour and type; Details is everything the card shows (title, company, logo, photo,
/// contacts, QR).
enum EditorTab: String, CaseIterable, Identifiable {
    case template, style, details

    var id: String { rawValue }

    var title: String {
        switch self {
        case .template: String(localized: "Template", bundle: .appStrings)
        case .style: String(localized: "Style", bundle: .appStrings)
        case .details: String(localized: "Details", bundle: .appStrings)
        }
    }
}

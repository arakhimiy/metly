/// CARD_EDITOR sections (SPEC §2.5.24): Template | Color | Type | Fields | Media.
enum EditorTab: String, CaseIterable, Identifiable {
    case template, color, type, fields, media

    var id: String { rawValue }

    var title: String {
        switch self {
        case .template: String(localized: "Template")
        case .color: String(localized: "Color")
        case .type: String(localized: "Type")
        case .fields: String(localized: "Fields")
        case .media: String(localized: "Media")
        }
    }
}

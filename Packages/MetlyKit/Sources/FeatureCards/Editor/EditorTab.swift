/// CARD_EDITOR sections (SPEC §2.5.24): Template | Color | Type | Fields | Media.
enum EditorTab: String, CaseIterable, Identifiable {
    case template, color, type, fields, media

    var id: String { rawValue }

    var title: String {
        switch self {
        case .template: "Template"
        case .color: "Color"
        case .type: "Type"
        case .fields: "Fields"
        case .media: "Media"
        }
    }
}

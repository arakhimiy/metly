/// People tab segmented filter.
enum PeopleFilter: String, CaseIterable, Identifiable, Hashable {
    case all, events, places, tags

    /// Shown in the picker. Places is left out: search already finds people by place and city.
    static let offered: [PeopleFilter] = [.all, .events, .tags]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: String(localized: "All", bundle: .appStrings)
        case .events: String(localized: "Events", bundle: .appStrings)
        case .places: String(localized: "Places", bundle: .appStrings)
        case .tags: String(localized: "Tags", bundle: .appStrings)
        }
    }
}

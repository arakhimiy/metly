/// People tab segmented filter.
enum PeopleFilter: String, CaseIterable, Identifiable, Hashable {
    case all, events, places, tags

    /// Shown in the picker. Places is left out: search already finds people by place and city.
    static let offered: [PeopleFilter] = [.all, .events, .tags]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: String(localized: "All")
        case .events: String(localized: "Events")
        case .places: String(localized: "Places")
        case .tags: String(localized: "Tags")
        }
    }
}

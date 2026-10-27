/// People tab segmented filter.
enum PeopleFilter: String, CaseIterable, Identifiable, Hashable {
    case all, events, places, tags

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

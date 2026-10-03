/// People tab segmented filter.
enum PeopleFilter: String, CaseIterable, Identifiable, Hashable {
    case all, events, places, tags

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .events: "Events"
        case .places: "Places"
        case .tags: "Tags"
        }
    }
}

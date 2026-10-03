/// CARD_CREATE steps pushed after "How do you want to start?" (SPEC §2.5.23; no AI path in v1).
enum CreateStep: Hashable {
    /// 2-column template gallery.
    case gallery
    /// Palette + Light / Dark.
    case style
    /// Card name + "Show on This Card".
    case details

    /// Progress shown under the navigation bar (method step = 0.2, done = 1).
    var progress: Double {
        switch self {
        case .gallery: 0.45
        case .style: 0.65
        case .details: 0.88
        }
    }
}

/// How the user starts a new card.
enum CreateMethod {
    case template, blank
}

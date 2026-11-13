/// CARD_CREATE steps pushed after the Templates gallery (the wizard's root).
enum CreateStep: Hashable {
    /// Palette + Light / Dark.
    case style
    /// Card name + "Show on This Card" (title, company, logo, photo, contacts, QR).
    case details

    /// Progress shown under the navigation bar (Templates = 1/3, done = 1).
    var progress: Double {
        switch self {
        case .style: 0.66
        case .details: 0.9
        }
    }

    /// The Templates gallery (root).
    static let galleryProgress = 0.33
}

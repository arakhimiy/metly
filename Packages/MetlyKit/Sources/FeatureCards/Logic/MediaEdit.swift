import Foundation

/// A pending change to a profile-level image (photo or logo) made inside the card editor.
/// Nothing is written to `Profile` until the editor's Done.
nonisolated enum MediaEdit: Equatable, Sendable {
    case unchanged
    case replaced(Data)
    case removed

    /// The image to show/store, given what the profile currently has.
    func resolved(_ current: Data?) -> Data? {
        switch self {
        case .unchanged: current
        case .replaced(let data): data
        case .removed: nil
        }
    }
}

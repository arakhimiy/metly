import Foundation
import MetlyData
import SwiftData

/// Live query for the signed-in user's profile (`@Query(ProfileQuery.current)`).
enum ProfileQuery {
    static var current: FetchDescriptor<Profile> {
        var descriptor = FetchDescriptor<Profile>(predicate: #Predicate { $0.deletedAt == nil })
        descriptor.fetchLimit = 1
        return descriptor
    }
}

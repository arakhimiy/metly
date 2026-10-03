import MetlyData
import SwiftData
import SwiftUI

/// Hands the signed-in user's profile to `content`, or shows an unavailable state.
struct ProfileReader<Content: View>: View {
    @Query(filter: #Predicate<Profile> { $0.deletedAt == nil }) private var profiles: [Profile]
    let content: (Profile) -> Content

    init(@ViewBuilder content: @escaping (Profile) -> Content) {
        self.content = content
    }

    var body: some View {
        if let profile = profiles.first {
            content(profile)
        } else {
            ContentUnavailableView(
                "No Profile",
                systemImage: "person.crop.circle.badge.exclamationmark",
                description: Text("Sign out and sign in again to set up your profile.")
            )
        }
    }
}

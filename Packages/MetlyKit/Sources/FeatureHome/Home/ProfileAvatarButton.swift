import MetlyData
import MetlyDesign
import SwiftUI

/// Toolbar avatar (photo or initials) → PROFILE tab.
struct ProfileAvatarButton: View {
    let profile: Profile?
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var size = 32

    var body: some View {
        Button(action: action) {
            InitialsAvatar(name: profile?.fullName ?? "", imageData: profile?.photoData, size: min(size, 44))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile")
        .accessibilityHint("Opens your profile")
    }
}

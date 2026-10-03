import MetlyDesign
import SwiftUI

/// Remote avatar with the initials avatar as placeholder / fallback. Decorative (rows carry the name).
struct PersonAvatar: View {
    let name: String
    var url: URL?
    var size: CGFloat

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                InitialsAvatar(name: name, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .accessibilityHidden(true)
    }
}

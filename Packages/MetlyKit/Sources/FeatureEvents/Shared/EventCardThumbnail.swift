import MetlyCardKit
import MetlyData
import SwiftUI

/// Small live card face (Card to Share). Decorative — rows provide the accessible name.
struct EventCardThumbnail: View {
    let card: Card
    let profile: Profile?

    @ScaledMetric(relativeTo: .body) private var width: CGFloat = 64

    var body: some View {
        CardFaceView(design: card.design, content: card.faceContent(profile: profile, audience: .connections))
            .frame(width: width)
            .cardFaceElevation()
            .accessibilityHidden(true)
    }
}

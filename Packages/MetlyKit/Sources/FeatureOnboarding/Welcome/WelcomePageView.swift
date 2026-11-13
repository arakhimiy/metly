import SwiftUI

/// One welcome page: hero illustration, title, subtitle.
struct WelcomePageView: View {
    let page: WelcomePage
    /// Drives one-shot symbol effects when the page becomes visible.
    let isCurrent: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        FillOrScrollView {
            VStack(spacing: 36) {
                Spacer(minLength: 8)

                // The illustration is decorative; at accessibility text sizes it would push the title and
                // subtitle under the page indicator, so the words get the whole page instead.
                if !dynamicTypeSize.isAccessibilitySize {
                    switch page {
                    case .share: ShareCardHero(isActive: isCurrent)
                    case .context: ContextHero(isActive: isCurrent)
                    case .followUp: FollowUpHero(isActive: isCurrent)
                    }
                }

                VStack(spacing: 12) {
                    Text(page.title)
                        .font(.largeTitle)
                        .bold()
                        .accessibilityAddTraits(.isHeader)
                    Text(page.subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

                // Room for the system page indicator.
                Spacer(minLength: 56)
            }
            .padding(.horizontal, 24)
        }
    }
}

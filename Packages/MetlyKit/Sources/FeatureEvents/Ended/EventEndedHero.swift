import SwiftUI

/// Flag icon, "{event} Ended" and the one-sentence summary. The flag bounces once on appear
/// unless Reduce Motion is on.
struct EventEndedHero: View {
    let eventName: String
    let summary: String
    let celebrate: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var badgeSize: CGFloat = 88

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "flag.checkered")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: badgeSize, height: badgeSize)
                .background(.tint.opacity(0.15), in: .circle)
                .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? false : celebrate)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("\(eventName) Ended")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(summary)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

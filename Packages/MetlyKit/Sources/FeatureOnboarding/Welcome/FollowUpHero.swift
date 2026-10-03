import MetlyCore
import SwiftUI

/// Page 3 — a follow-up notification and the one-tap day choices.
struct FollowUpHero: View {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title3) private var iconSize = 40.0

    var body: some View {
        VStack(spacing: 20) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bell.badge.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.red, .white)
                    .font(.title3)
                    .frame(width: iconSize, height: iconSize)
                    .background(Color.accentColor.gradient, in: .rect(cornerRadius: iconSize * 0.24))
                    .symbolEffect(.wiggle, value: isActive)
                    .symbolEffectsRemoved(reduceMotion)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(verbatim: Brand.appName)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Text("now")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Text("Follow up with \(OnboardingSamples.contactName)")
                        .font(.subheadline.weight(.semibold))
                    Text("Design review you promised at \(OnboardingSamples.eventName).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 22))

            ViewThatFits {
                HStack(spacing: 8) { chips }
                VStack(spacing: 8) { chips }
            }
        }
        .containerRelativeFrame(.horizontal) { length, _ in min(length * 0.88, 380) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Example notification: Follow up with \(OnboardingSamples.contactName). Design review you promised at \(OnboardingSamples.eventName). Choices: Tomorrow, In 3 Days, Next Week.")
        .accessibilityAddTraits(.isImage)
    }

    @ViewBuilder
    private var chips: some View {
        DayChip(title: "Tomorrow", isSelected: true)
        DayChip(title: "In 3 Days", isSelected: false)
        DayChip(title: "Next Week", isSelected: false)
    }
}

private struct DayChip: View {
    let title: LocalizedStringKey
    let isSelected: Bool

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.tint))
            .background(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tint.opacity(0.12)), in: .capsule)
    }
}

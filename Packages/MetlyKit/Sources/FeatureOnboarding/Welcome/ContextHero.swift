import MetlyDesign
import SwiftUI

/// Page 2 — a contact with auto-filled "Where You Met" context and a voice note.
struct ContextHero: View {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sampleTime: String {
        let time = Calendar.current.date(bySettingHour: 14, minute: 32, second: 0, of: .now) ?? .now
        return time.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                InitialsAvatar(name: OnboardingSamples.contactName, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: OnboardingSamples.contactName)
                        .font(.headline)
                    Text(verbatim: OnboardingSamples.contactRole)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }

            Divider()

            VStack(spacing: 10) {
                // "Auto" sits with the context it fills in, so the name row keeps its full width.
                HStack {
                    Text("Where You Met")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Spacer(minLength: 8)
                    Label("Auto", systemImage: "wand.and.sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.tint.opacity(0.12), in: .capsule)
                        .symbolEffect(.bounce, value: isActive)
                        .symbolEffectsRemoved(reduceMotion)
                }
                ContextLine(title: "Event", systemImage: "calendar", value: OnboardingSamples.eventName)
                ContextLine(title: "Place", systemImage: "mappin.and.ellipse", value: OnboardingSamples.placeName)
                ContextLine(title: "Time", systemImage: "clock", value: String(localized: "Today, \(sampleTime)"))
            }

            Divider()

            Label {
                Text("Wants a design review next week.")
                    .font(.subheadline)
            } icon: {
                Image(systemName: "waveform")
                    .foregroundStyle(.tint)
                    .symbolEffect(.variableColor.iterative, isActive: isActive && !reduceMotion)
            }
        }
        .padding(18)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 22))
        .containerRelativeFrame(.horizontal) { length, _ in min(length * 0.86, 380) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Example: \(OnboardingSamples.contactName), met at \(OnboardingSamples.eventName), \(OnboardingSamples.placeName), today. Voice note: wants a design review next week.")
        .accessibilityAddTraits(.isImage)
    }
}

private struct ContextLine: View {
    let title: LocalizedStringKey
    let systemImage: String
    let value: String

    var body: some View {
        LabeledContent {
            Text(verbatim: value)
                .foregroundStyle(.primary)
        } label: {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }
}

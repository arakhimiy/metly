import MetlyCore
import MetlyData
import MetlyDesign
import SwiftUI

/// "Recent" (SPEC §2.5.7): the last three people met → CONNECTION_DETAIL; See All → PEOPLE tab.
struct RecentSection: View {
    let people: [Connection]
    let now: Date

    @Environment(AppRouter.self) private var router

    var body: some View {
        Section {
            ForEach(people) { person in
                NavigationLink(value: PushDestination.connectionDetail(id: person.id)) {
                    RecentPersonRow(person: person, now: now)
                }
            }
        } header: {
            HomeSectionHeader(Text("Recent")) {
                Button("See All", action: seeAll)
            }
        }
        .headerProminence(.increased)
    }

    private func seeAll() {
        router.select(.people)
    }
}

/// Avatar, name, "{event} · {city}" and a compact "2d" / "now" / "1mo".
struct RecentPersonRow: View {
    let person: Connection
    let now: Date

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let meta = PersonText.meetingMeta(of: person)
        let metAt = person.context.metAt
        HStack(spacing: 12) {
            InitialsAvatar(name: person.fullName, imageData: person.avatarData, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.fullName)
                    .font(.headline)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                if !meta.isEmpty {
                    Text(meta)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                }
            }
            Spacer(minLength: 8)
            Text(CompactRelativeTime.string(from: metAt, now: now))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text("Met \(metAt.formatted(.relative(presentation: .named)))"))
    }
}

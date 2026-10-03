import MetlyCore
import MetlyData
import MetlyDesign
import SwiftData
import SwiftUI

/// Settings › Privacy › Blocked People (SPEC §9 Q34): list with Unblock.
struct BlockedPeopleScreen: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Connection> { $0.deletedAt == nil && $0.isBlocked }, sort: \Connection.fullName)
    private var blocked: [Connection]

    var body: some View {
        List {
            if !blocked.isEmpty {
                Section {
                    ForEach(blocked) { person in
                        BlockedPersonRow(person: person) { unblock(person) }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button("Unblock", systemImage: "hand.raised.slash") { unblock(person) }
                                    .tint(.accentColor)
                            }
                    }
                } footer: {
                    Text("Blocked people can't see your cards or send you connect requests. They aren't told you blocked them.")
                }
            }
        }
        .overlay {
            if blocked.isEmpty {
                ContentUnavailableView("No Blocked People", systemImage: "hand.raised",
                                       description: Text("People you block can't see your cards. You can block someone from their page in People."))
            }
        }
        .navigationTitle("Blocked People")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func unblock(_ person: Connection) {
        PeopleActions.unblock(person, in: modelContext)
        router.showToast("Unblocked \(PersonName.first(person.fullName))", systemImage: "hand.raised.slash")
    }
}

private struct BlockedPersonRow: View {
    let person: Connection
    let onUnblock: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            InitialsAvatar(name: person.fullName, imageData: person.avatarData, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.fullName)
                    .font(.body)
                if !role.isEmpty {
                    Text(role)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            Button("Unblock", action: onUnblock)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .accessibilityLabel("Unblock \(person.fullName)")
        }
    }

    private var role: String {
        [person.jobTitle, person.company].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

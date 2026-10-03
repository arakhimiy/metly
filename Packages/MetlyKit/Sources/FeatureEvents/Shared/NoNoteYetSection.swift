import MetlyData
import MetlyDesign
import SwiftUI

/// "No Note Yet" — people without a private note, each with an Add Note button (→ ADD_CONTEXT).
/// Shows at most `limit` people (SPEC §2.5.31: ≤ 4).
struct NoNoteYetSection: View {
    let people: [Connection]
    var limit = 4
    let onAddNote: (Connection) -> Void

    var body: some View {
        if !people.isEmpty {
            Section {
                ForEach(people.prefix(limit)) { person in
                    NoNoteYetRow(person: person) { onAddNote(person) }
                }
            } header: {
                Text("No Note Yet")
            } footer: {
                if people.count > limit {
                    Text("And \(people.count - limit) more. Notes stay private — only you can see them.")
                } else {
                    Text("Add a note while you still remember the conversation. Only you can see it.")
                }
            }
        }
    }
}

/// Name + Add Note; the button moves under the name at accessibility text sizes.
private struct NoNoteYetRow: View {
    let person: Connection
    let onAddNote: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            HStack(spacing: 12) {
                InitialsAvatar(name: person.fullName, imageData: person.avatarData, size: 32)
                Text(person.fullName)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("Add Note", action: onAddNote)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .fixedSize()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

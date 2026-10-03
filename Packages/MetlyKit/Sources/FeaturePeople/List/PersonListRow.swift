import MetlyCore
import MetlyData
import SwiftUI

/// Row-level actions the People list hands to every row.
struct PersonRowActions {
    var addNote: (Connection) -> Void
    var remove: (Connection) -> Void
}

/// A tappable People row with swipe actions (Note / Remove) and MENU_PERSON_ROW (Open / Add Note / Remove).
struct PersonListRow: View {
    let person: Connection
    let meta: PersonRowMeta
    let actions: PersonRowActions

    @Environment(AppRouter.self) private var router

    var body: some View {
        Group {
            if needsContextFirst {
                Button(action: open) {
                    HStack {
                        PersonRow(person: person, meta: meta)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.forward")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .contentShape(.rect)
                }
                .foregroundStyle(.primary)
                .accessibilityHint("Opens Add Context")
            } else {
                NavigationLink(value: PushDestination.connectionDetail(id: person.id)) {
                    PersonRow(person: person, meta: meta)
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Remove", systemImage: "trash") { actions.remove(person) }
                .tint(.red)
            Button("Note", systemImage: "square.and.pencil") { actions.addNote(person) }
                .tint(.orange)
        }
        .contextMenu {
            Button("Open", systemImage: "person.crop.circle", action: open)
            Button("Add Note", systemImage: "square.and.pencil") { actions.addNote(person) }
            Divider()
            Button("Remove", systemImage: "trash", role: .destructive) { actions.remove(person) }
        }
    }

    /// A web share-back without a note opens on ADD_CONTEXT (SPEC §2.5.11), on top of the detail.
    private var needsContextFirst: Bool {
        person.source == .webShareBack && person.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func open() {
        router.push(.connectionDetail(id: person.id))
        if needsContextFirst {
            router.present(.addContext(connectionID: person.id))
        }
    }
}

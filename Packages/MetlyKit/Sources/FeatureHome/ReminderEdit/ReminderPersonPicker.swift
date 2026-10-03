import MetlyCore
import MetlyData
import MetlyDesign
import SwiftData
import SwiftUI

/// MENU_PERSON_PICKER as a searchable pushed list (most recent connections first, checkmark on the current one).
struct ReminderPersonPicker: View {
    @Binding var selection: UUID?

    @Query(Connection.live) private var people: [Connection]
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let results = people.filter { PersonText.matches($0, query: query) }
        List(results) { person in
            Button {
                select(person)
            } label: {
                HStack {
                    ReminderPersonLabel(person: person)
                    Spacer(minLength: 8)
                    if person.id == selection {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(.rect)
            }
            .foregroundStyle(.primary)
            .accessibilityAddTraits(person.id == selection ? .isSelected : [])
        }
        .overlay {
            if people.isEmpty {
                ContentUnavailableView("No Connections Yet", systemImage: "person.2",
                                       description: Text("Scan someone's card or open Connect. Your notes about them stay private."))
            } else if results.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
        .navigationTitle("Choose a Person")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func select(_ person: Connection) {
        selection = person.id
        dismiss()
    }
}

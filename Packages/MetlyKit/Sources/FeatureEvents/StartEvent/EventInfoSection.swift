import SwiftUI

/// Name (required), Place and optional City.
struct EventInfoSection: View {
    @Binding var draft: EventDraft
    var focus: FocusState<EventField?>.Binding

    var body: some View {
        Section {
            TextField("Name", text: $draft.name, prompt: Text("Event name"))
                .textInputAutocapitalization(.words)
                .submitLabel(.next)
                .focused(focus, equals: .name)
                .onSubmit { focus.wrappedValue = .place }
            TextField("Place", text: $draft.place, prompt: Text("Where is it?"))
                .textContentType(.location)
                .textInputAutocapitalization(.words)
                .submitLabel(.next)
                .focused(focus, equals: .place)
                .onSubmit { focus.wrappedValue = .city }
            TextField("City", text: $draft.city, prompt: Text("City (optional)"))
                .textContentType(.addressCity)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .focused(focus, equals: .city)
        } header: {
            Text("Event")
        } footer: {
            if draft.trimmedName.isEmpty {
                Text("Add an event name.")
            }
        }
    }
}

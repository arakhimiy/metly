import MetlyCapture
import MetlyCore
import MetlyData
import SwiftData
import SwiftUI

/// JUST_MET (SPEC §2.5.33 / §3.8): "Who did you just meet?" after showing the QR or sharing.
/// Saves a lightweight `.justMet` connection marked `isPendingMerge` so a later web share-back can be merged
/// (with confirmation) into it.
struct JustMetScreen: View {
    let cardID: UUID?

    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var draft = CaptureDraft()
    @State private var isLoaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Their Name", text: $name, prompt: Text("Their name (optional)"))
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                } header: {
                    Text("Name")
                }
                if isLoaded {
                    ContextCaptureForm(draft: $draft, sections: [.whereYouMet, .note, .followUp])
                }
                Section {
                } footer: {
                    Text("If they share their contact from your page later, \(Brand.appName) asks before merging the two.")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Who did you just meet?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip", action: router.dismiss)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
            .task { load() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// Something to remember them by: a name, a note or a reminder.
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            || !draft.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || draft.followUp != nil
    }

    private func load() {
        guard !isLoaded else { return }
        draft = .capture(for: nil, in: modelContext)
        isLoaded = true
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let context = draft.meetingContext
        let person = Connection(fullName: trimmed.isEmpty ? JustMetNaming.placeholder(eventName: context.eventName) : trimmed,
                                source: .justMet, context: context)
        person.isPendingMerge = true
        person.mySharedCardID = cardID ?? modelContext.cardToShare()?.id
        modelContext.insert(person)

        // The quick-pick chips already enforce the Free limit; if it was hit meanwhile, the person is
        // still saved without the reminder (toast falls back to "Saved {first}").
        let result = draft.apply(to: person, in: modelContext, limits: services.entitlements.limits)
        router.dismiss()
        let fallback = trimmed.isEmpty ? String(localized: "Saved") : String(localized: "Saved \(PersonName.first(trimmed))")
        router.showToast(result.toastMessage(otherwise: fallback), systemImage: "checkmark.circle")
    }
}

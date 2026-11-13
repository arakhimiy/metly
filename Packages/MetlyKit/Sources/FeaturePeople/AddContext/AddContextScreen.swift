import MetlyCapture
import MetlyCore
import MetlyData
import MetlyNetworking
import SwiftData
import SwiftUI

/// ADD_CONTEXT (SPEC §2.5.32): the capture block for an existing person, with the share-back merge prompt,
/// followed by their contact info (every phone with a label menu, add / delete, email, Telegram…).
struct AddContextScreen: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext

    @Query(Connection.live) private var people: [Connection]

    /// The record being edited — switches to the just-met record after a merge.
    @State private var targetID: UUID
    @State private var draft = CaptureDraft()
    @State private var contactInfo = ContactInfoDraft()
    @State private var loadedID: UUID?
    @State private var dismissedCandidates: Set<UUID> = []
    @State private var showsLimitAlert = false
    @State private var limitCount = 0
    @State private var mergeCount = 0

    init(connectionID: UUID) {
        _targetID = State(initialValue: connectionID)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let person {
                    Form {
                        AddContextHeaderSection(person: person)
                        if let candidate = mergeCandidate(for: person) {
                            MergePromptSection(candidate: candidate,
                                               onMerge: { merge(person, into: candidate) },
                                               onDismiss: { dismissedCandidates.insert(candidate.id) })
                        }
                        if loadedID == person.id {
                            ContextCaptureForm(draft: $draft)
                            ContactInfoEditor(draft: $contactInfo)
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .task(id: person.id) { load(person) }
                    .onChange(of: contactInfo) {
                        // A number or username typed here decides the channel of a reminder picked next.
                        if draft.followUp == nil { draft.preferredChannel = contactInfo.preferredChannel }
                    }
                } else {
                    ContentUnavailableView("Connection Not Found", systemImage: "person.crop.circle.badge.questionmark")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: router.dismiss)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(person == nil || loadedID == nil)
                }
            }
            .followUpLimitAlert(isPresented: $showsLimitAlert, openCount: limitCount)
            .sensoryFeedback(.success, trigger: mergeCount)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var person: Connection? {
        people.first { $0.id == targetID }
    }

    private var title: String {
        guard let person, !person.note.isEmpty || !person.tags.isEmpty else { return String(localized: "Add Context", bundle: .appStrings) }
        return String(localized: "Edit Context", bundle: .appStrings)
    }

    private func mergeCandidate(for person: Connection) -> Connection? {
        ShareBackMerger.candidates(for: person, among: people).first { !dismissedCandidates.contains($0.id) }
    }

    private func load(_ person: Connection) {
        guard loadedID != person.id else { return }
        let isFirstCapture = person.note.isEmpty && person.tags.isEmpty
        draft = isFirstCapture ? .capture(for: person, in: modelContext) : CaptureDraft(editing: person)
        contactInfo = ContactInfoDraft(connection: person)
        loadedID = person.id
    }

    private func merge(_ shareBack: Connection, into justMet: Connection) {
        ShareBackMerger.merge(shareBack, into: justMet, in: modelContext)
        mergeCount += 1
        loadedID = nil
        targetID = justMet.id
        router.showToast(String(localized: "Merged with your QR note", bundle: .appStrings), systemImage: "arrow.triangle.merge")
    }

    private func save() {
        guard let person else { return }
        contactInfo.apply(to: person)   // saved together with the context below
        let result = draft.apply(to: person, in: modelContext, limits: services.entitlements.limits)
        if case .limitReached(let count) = result.followUp {
            limitCount = count
            showsLimitAlert = true
            return
        }
        router.dismiss()
        router.showToast(result.toastMessage(otherwise: String(localized: "Context Saved", bundle: .appStrings)), systemImage: "checkmark.circle")
    }
}

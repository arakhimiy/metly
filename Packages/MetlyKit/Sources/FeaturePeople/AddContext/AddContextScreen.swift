import MetlyCapture
import MetlyCore
import MetlyData
import SwiftData
import SwiftUI

/// ADD_CONTEXT (SPEC §2.5.32): the capture block for an existing person, with the share-back merge prompt.
struct AddContextScreen: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext

    @Query(Connection.live) private var people: [Connection]

    /// The record being edited — switches to the just-met record after a merge.
    @State private var targetID: UUID
    @State private var draft = CaptureDraft()
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
                        }
                    }
                    .task(id: person.id) { load(person) }
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
        guard let person, !person.note.isEmpty || !person.tags.isEmpty else { return "Add Context" }
        return "Edit Context"
    }

    private func mergeCandidate(for person: Connection) -> Connection? {
        ShareBackMerger.candidates(for: person, among: people).first { !dismissedCandidates.contains($0.id) }
    }

    private func load(_ person: Connection) {
        guard loadedID != person.id else { return }
        let isFirstCapture = person.note.isEmpty && person.tags.isEmpty
        draft = isFirstCapture ? .capture(for: person, in: modelContext) : CaptureDraft(editing: person)
        loadedID = person.id
    }

    private func merge(_ shareBack: Connection, into justMet: Connection) {
        ShareBackMerger.merge(shareBack, into: justMet, in: modelContext)
        mergeCount += 1
        loadedID = nil
        targetID = justMet.id
        router.showToast("Merged with your QR note", systemImage: "arrow.triangle.merge")
    }

    private func save() {
        guard let person else { return }
        let result = draft.apply(to: person, in: modelContext, limits: services.entitlements.limits)
        if case .limitReached(let count) = result.followUp {
            limitCount = count
            showsLimitAlert = true
            return
        }
        router.dismiss()
        router.showToast(result.toastMessage(otherwise: "Context Saved"), systemImage: "checkmark.circle")
    }
}

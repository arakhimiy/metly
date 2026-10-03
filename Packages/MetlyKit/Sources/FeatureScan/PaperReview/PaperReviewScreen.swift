import MetlyCapture
import MetlyCore
import MetlyData
import SwiftData
import SwiftUI

/// PAPER_REVIEW (SPEC §2.5.10): check what was read from a paper card, add the context
/// (where you met · note · tags · follow-up), then Save → `Connection(source: .paper)` →
/// CONNECTION_DETAIL. The photo is shown here only; it isn't stored (SPEC §9 Q44).
struct PaperReviewScreen: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Query(Connection.live) private var people: [Connection]

    private let imageData: Data?
    private let detectedCount: Int

    @State private var details: PaperCardDetails
    @State private var hints: [PaperField: PaperFieldHint]
    @State private var capture = CaptureDraft()
    @State private var isCaptureReady = false
    @State private var showsLimitAlert = false
    @State private var limitCount = 0
    @FocusState private var focusedField: PaperField?

    init(draft: PaperCardDraft) {
        imageData = draft.imageData
        detectedCount = draft.detectedFieldCount
        _details = State(initialValue: PaperCardDetails(draft: draft))
        _hints = State(initialValue: PaperFieldHint.assess(draft))
    }

    var body: some View {
        Form {
            if let imageData {
                PaperImageSection(imageData: imageData, detectedCount: detectedCount, onRetake: retake)
            }
            PaperDetailsSection(details: $details, hints: hints, focusedField: $focusedField)
            if let existing {
                Section {
                    Button("Open \(existing.fullName)", systemImage: "person.crop.circle.badge.checkmark") { open(existing) }
                } footer: {
                    Text("Someone with the same phone, email or Telegram is already in your People.")
                }
            }
            if isCaptureReady {
                ContextCaptureForm(draft: $capture)
            }
        }
        .navigationTitle("Paper Card")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(!details.canSave)
            }
        }
        .followUpLimitAlert(isPresented: $showsLimitAlert, openCount: limitCount)
        .task { prepareCapture() }
        .onChange(of: details) { old, new in
            detailsChanged(from: old, to: new)
        }
    }

    /// Someone already in People with the same phone, email or Telegram.
    private var existing: Connection? {
        ScanConnectionFactory.existing(matching: details.contactFields, among: people)
    }

    // MARK: Actions

    private func prepareCapture() {
        guard !isCaptureReady else { return }
        capture = .capture(for: nil, in: modelContext)
        capture.preferredChannel = FollowUpPolicy.preferredChannel(phone: details.phone, email: details.email,
                                                                   telegram: details.telegram)
        isCaptureReady = true
    }

    /// Edited values lose their hint; the reminder channel follows the available fields.
    private func detailsChanged(from old: PaperCardDetails, to new: PaperCardDetails) {
        for field in PaperField.allCases where old[field] != new[field] {
            hints[field] = nil
        }
        capture.preferredChannel = FollowUpPolicy.preferredChannel(phone: new.phone, email: new.email, telegram: new.telegram)
    }

    private func retake() {
        router.pop()
    }

    private func open(_ person: Connection) {
        router.open(.connectionDetail(id: person.id), in: .people)
    }

    private func save() {
        let limits = services.entitlements.limits
        // Backstop for the capture block's own check: never save half way through a blocked reminder.
        if capture.followUp != nil, !FollowUpPolicy.canSchedule(hasOpenReminder: false, in: modelContext, limits: limits) {
            limitCount = FollowUpPolicy.openCount(in: modelContext)
            showsLimitAlert = true
            return
        }
        let connection = ScanConnectionFactory.insertConnection(from: details.draft, source: .paper, in: modelContext)
        let result = capture.apply(to: connection, in: modelContext, limits: limits)
        router.showToast(result.toastMessage(otherwise: "Contact Saved"), systemImage: "checkmark.circle")

        let tab = router.selectedTab
        if tab != .people { router.popToRoot(tab) }
        router.open(.connectionDetail(id: connection.id), in: .people)
    }
}

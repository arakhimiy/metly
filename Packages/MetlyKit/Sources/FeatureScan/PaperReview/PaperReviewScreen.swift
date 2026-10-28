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
    private let recognizedText: [String]

    @State private var details: PaperCardDetails
    @State private var hints: [PaperField: PaperFieldHint]
    @State private var phoneHints: [PaperPhoneRow.ID: PaperFieldHint]
    @State private var capture = CaptureDraft()
    @State private var isCaptureReady = false
    @State private var showsLimitAlert = false
    @State private var limitCount = 0
    @State private var reassignCount = 0
    @FocusState private var focus: PaperFocus?
    /// Contact rows added with + Add Contact that are still empty.
    @State private var addedFields: Set<PaperField> = []

    /// - Parameter scan: the reader's full result (recognized text, sure fields); nil = the draft alone.
    init(draft: PaperCardDraft, scan: PaperScan? = nil) {
        imageData = draft.imageData
        detectedCount = draft.detectedFieldCount
        recognizedText = scan?.recognizedText ?? []
        let details = PaperCardDetails(draft: draft)
        _details = State(initialValue: details)
        var hints = PaperFieldHint.assess(draft, confident: scan?.confidentFields ?? [])
        hints[.phone] = nil
        _hints = State(initialValue: hints)
        _phoneHints = State(initialValue: Dictionary(uniqueKeysWithValues: details.phones.map { row in
            (row.id, PhoneFormat.isPlausible(row.value) ? PaperFieldHint.detected : .guessed)
        }))
    }

    var body: some View {
        Form {
            if let imageData {
                PaperImageSection(imageData: imageData, detectedCount: detectedCount, onRetake: retake)
            }
            PaperDetailsSection(details: $details, hints: hints, focus: $focus, onSwap: swapNameAndCompany)
            PaperContactInfoSection(details: $details, added: $addedFields, hints: hints, phoneHints: phoneHints, focus: $focus)
            if !recognizedText.isEmpty {
                PaperRecognizedTextSection(lines: recognizedText, details: details, onUse: use)
            }
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
        .sensoryFeedback(.selection, trigger: reassignCount)
        .task { prepareCapture() }
        .onChange(of: details) { old, new in
            detailsChanged(from: old, to: new)
        }
    }

    /// Someone already in People with the same phone (any of them), email or Telegram.
    private var existing: Connection? {
        ScanConnectionFactory.existing(matching: details.contactFields, phones: details.phones.map(\.value), among: people)
    }

    // MARK: Actions

    private func prepareCapture() {
        guard !isCaptureReady else { return }
        capture = .capture(for: nil, in: modelContext)
        capture.preferredChannel = preferredChannel(for: details)
        isCaptureReady = true
    }

    /// Edited values lose their hint; the reminder channel follows the available fields.
    private func detailsChanged(from old: PaperCardDetails, to new: PaperCardDetails) {
        for field in PaperField.allCases where field != .phone && old[field] != new[field] {
            hints[field] = nil
        }
        let oldValues = Dictionary(uniqueKeysWithValues: old.phones.map { ($0.id, $0.value) })
        for row in new.phones where oldValues[row.id] != row.value {
            phoneHints[row.id] = nil
        }
        capture.preferredChannel = preferredChannel(for: new)
    }

    private func preferredChannel(for details: PaperCardDetails) -> FollowUpChannel {
        FollowUpPolicy.preferredChannel(phone: details.savedPhones.primary?.value ?? "", email: details.email,
                                        telegram: details.telegram)
    }

    private func use(_ line: String, as use: PaperLineUse) {
        details.use(line, as: use)
        reassignCount += 1
    }

    private func swapNameAndCompany() {
        withAnimation {
            details.swapNameAndCompany()
        }
        reassignCount += 1
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
        router.showToast(result.toastMessage(otherwise: String(localized: "Contact Saved")), systemImage: "checkmark.circle")

        let tab = router.selectedTab
        if tab != .people { router.popToRoot(tab) }
        router.open(.connectionDetail(id: connection.id), in: .people)
    }
}

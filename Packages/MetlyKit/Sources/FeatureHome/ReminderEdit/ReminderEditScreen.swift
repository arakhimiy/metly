import MetlyCapture
import MetlyCore
import MetlyData
import SwiftData
import SwiftUI

/// REMINDER_EDIT (large sheet, SPEC §2.5.34): Person · Reminder · When · Reply Via (+ Open Person /
/// Delete when editing). Cancel / Save; Free limit on create (ALERT_FU_LIMIT → paywall).
struct ReminderEditScreen: View {
    let existing: FollowUp?
    let isPersonFixed: Bool

    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext

    @State private var form: ReminderForm
    @State private var showsLimitAlert: Bool
    @State private var openCount: Int
    @State private var isConfirmingDelete = false
    private let original: ReminderForm

    /// `showsLimitAlert` / `openCount` let previews show ALERT_FU_LIMIT directly.
    init(existing: FollowUp?, person: Connection?, isPersonFixed: Bool, showsLimitAlert: Bool = false, openCount: Int = 0) {
        self.existing = existing
        self.isPersonFixed = isPersonFixed
        let form: ReminderForm = if let existing {
            .editing(title: existing.title, dueAt: existing.dueAt, channel: existing.channel, personID: existing.connection?.id)
        } else {
            .new(personID: person?.id, channel: FollowUpPolicy.preferredChannel(for: person))
        }
        _form = State(initialValue: form)
        _showsLimitAlert = State(initialValue: showsLimitAlert)
        _openCount = State(initialValue: openCount)
        original = form
    }

    var body: some View {
        let person = form.personID.flatMap { modelContext.record(Connection.self, id: $0) }
        NavigationStack {
            Form {
                ReminderPersonSection(person: person, isFixed: isPersonFixed, selection: $form.personID)
                Section {
                    TextField("To Do", text: $form.title, prompt: Text("Follow up"))
                        .submitLabel(.done)
                } header: {
                    Text("Reminder")
                }
                ReminderWhenSection(form: $form, minimumDay: ReminderForm.minimumDay(existingDue: existing?.dueAt))
                ReminderChannelSection(channel: $form.channel, person: person)
                if existing != nil {
                    ReminderEditExtras(person: person, onOpenPerson: openPerson, onDelete: confirmDelete)
                }
            }
            .navigationTitle(existing == nil ? "New Reminder" : "Edit Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!form.canSave)
                }
            }
            .onChange(of: form.personID) { _, newID in
                updateDefaultChannel(for: newID)
            }
            .followUpLimitAlert(isPresented: $showsLimitAlert, openCount: openCount)
            .alert("Delete Reminder?", isPresented: $isConfirmingDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive, action: delete)
            } message: {
                Text("You won’t be reminded to follow up with \(PersonText.firstName(PersonText.displayName(person))).")
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(form != original)
    }

    // MARK: Actions

    /// New reminders follow the chosen person's best channel (Telegram, else Email, else Call).
    private func updateDefaultChannel(for personID: UUID?) {
        guard existing == nil else { return }
        let person = personID.flatMap { modelContext.record(Connection.self, id: $0) }
        form.channel = FollowUpPolicy.preferredChannel(for: person)
    }

    private func save() {
        switch ReminderEditor.save(form, existing: existing, in: modelContext, limits: services.entitlements.limits) {
        case .created:
            services.sync.requestSync()
            router.showToast(String(localized: "Reminder Set", bundle: .appStrings), systemImage: "bell")
            router.dismiss()
            Task { await FollowUpNotificationScheduler.requestAuthorizationIfNeeded() }
        case .updated:
            services.sync.requestSync()
            router.showToast(String(localized: "Reminder Updated", bundle: .appStrings), systemImage: "bell")
            router.dismiss()
        case .limitReached(let count):
            openCount = count
            showsLimitAlert = true
        case .missingPerson:
            router.showToast(String(localized: "Choose a person first", bundle: .appStrings), systemImage: "person.crop.circle.badge.questionmark")
        }
    }

    private func cancel() {
        router.dismiss()
    }

    private func confirmDelete() {
        isConfirmingDelete = true
    }

    private func delete() {
        guard let existing else { return }
        FollowUpMutations.delete(existing, in: modelContext)
        services.sync.requestSync()
        router.showToast(String(localized: "Reminder Deleted", bundle: .appStrings), systemImage: "trash")
        router.dismiss()
    }

    /// Opens the person in the current tab (or just closes when their detail is already underneath).
    private func openPerson() {
        guard let id = form.personID else { return }
        router.dismiss()
        let destination = PushDestination.connectionDetail(id: id)
        if router.paths[router.selectedTab]?.last != destination {
            router.push(destination)
        }
    }
}

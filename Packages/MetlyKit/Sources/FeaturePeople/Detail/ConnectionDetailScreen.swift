import MetlyCapture
import MetlyCore
import MetlyData
import SwiftData
import SwiftUI

/// CONNECTION_DETAIL (SPEC §2.5.12) — loads the person live by id.
struct ConnectionDetailScreen: View {
    @Query private var matches: [Connection]

    init(connectionID: UUID) {
        let id = connectionID
        _matches = Query(filter: #Predicate<Connection> { $0.id == id })
    }

    var body: some View {
        if let person = matches.first, !person.isDeleted {
            ConnectionDetailContent(person: person)
        } else {
            ContentUnavailableView("Connection Not Found", systemImage: "person.crop.circle.badge.questionmark",
                                   description: Text("This person may have been removed."))
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct ConnectionDetailContent: View {
    let person: Connection

    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @State private var contactDraft: ContactDraft?
    @State private var savedToContacts = 0

    var body: some View {
        List {
            DetailHeaderSection(person: person)
            QuickActionsSection(person: person, onSave: saveToContacts)
            if person.isMerged {
                MergedBannerSection()
            }
            WhereYouMetDetailSection(person: person)
            NoteDetailSection(person: person, onEdit: editContext)
            FollowUpDetailSection(person: person)
            EarlierMeetingsSection(meetings: person.previousMeetings)
            ContactInfoSection(person: person)
            SharedCardSection(person: person, sharedCardName: sharedCardName)
            DangerZoneSection(person: person)
        }
        .navigationTitle(person.fullName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit", action: editContext)
            }
        }
        .contactSaver(item: $contactDraft, onCompletion: contactSaveFinished)
        .sensoryFeedback(.success, trigger: savedToContacts)
    }

    private var sharedCardName: String? {
        guard let id = person.mySharedCardID else { return nil }
        return modelContext.record(Card.self, id: id)?.name
    }

    private func editContext() {
        router.present(.addContext(connectionID: person.id))
    }

    private func saveToContacts() {
        contactDraft = ContactDraft(connection: person)
    }

    private func contactSaveFinished(_ saved: Bool) {
        guard saved else { return }
        savedToContacts += 1
        router.showToast("Added to Contacts", systemImage: "person.crop.circle.badge.checkmark")
    }
}

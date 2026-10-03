import MetlyCapture
import MetlyCore
import MetlyData
import MetlyNetworking
import SwiftData
import SwiftUI

/// SCANNED_CARD for someone's Metly card: card face, contact rows and
/// Connect (request, PLAN Q8) · Add to People · Save to Contacts.
struct MetlyCardDetail: View {
    let card: PublicCardDTO
    let snapshot: CardSnapshot
    let model: ScannedCardModel

    @Environment(MetlyClient.self) private var client
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Query(Connection.live) private var people: [Connection]

    @State private var connectAttempt: UUID?
    @State private var contactDraft: ContactDraft?
    @State private var addedCount = 0

    var body: some View {
        @Bindable var model = model
        List {
            ScannedCardHeader(snapshot: snapshot)
            if isSelf {
                Section {
                    Label("This is your card.", systemImage: "person.crop.rectangle")
                        .foregroundStyle(.secondary)
                }
            } else {
                ConnectActionSection(firstName: firstName, phase: model.connectPhase, isInPeople: existing != nil,
                                     showsConnectHint: !isConnected, onConnect: connect, onCancel: cancelConnect,
                                     onOpenInPeople: openInPeople)
            }
            ContactFieldsSection(fields: snapshot.fields)
            if !isSelf {
                Section {
                    if existing == nil {
                        Button("Add to People", systemImage: "person.crop.circle.badge.plus", action: addToPeople)
                    } else if !isConnected, model.connectPhase == .idle || model.connectPhase == .noResponse {
                        Button("Connect", systemImage: "person.badge.plus", action: connect)
                    }
                    Button("Save to Contacts", systemImage: "square.and.arrow.down", action: saveToContacts)
                } footer: {
                    if existing == nil {
                        Text("Add to People keeps \(firstName) with your notes without sending a request.")
                    }
                }
            }
        }
        .contactSaver(item: $contactDraft, onCompletion: contactSaved)
        .task(id: connectAttempt) {
            guard connectAttempt != nil else { return }
            await model.connect(to: card, client: client, modelContext: modelContext, router: router)
        }
        .alert("Couldn’t Connect", isPresented: $model.showsError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .sensoryFeedback(.success, trigger: model.connectPhase) { _, new in new == .accepted }
        .sensoryFeedback(.warning, trigger: model.connectPhase) { _, new in new == .noResponse }
        .sensoryFeedback(.success, trigger: addedCount)
    }

    // MARK: State

    private var firstName: String {
        card.owner?.firstName ?? snapshot.faceContent.firstName
    }

    private var isSelf: Bool {
        card.viewer?.isSelf == true
    }

    /// Accepted connection on the server (their connections-only fields are visible).
    private var isConnected: Bool {
        card.viewer?.isConnected == true
    }

    /// Already in the owner's People (connected, added, or saved offline).
    private var existing: Connection? {
        ScanConnectionFactory.existing(remoteUserID: card.owner?.userID, among: people)
            ?? card.viewer?.connectionID.flatMap { id in people.first { $0.id == id } }
    }

    // MARK: Actions

    private func connect() {
        connectAttempt = UUID()
    }

    private func cancelConnect() {
        model.withdrawsOnCancel = true
        connectAttempt = nil
    }

    private func openInPeople() {
        guard let existing else { return }
        router.open(.connectionDetail(id: existing.id), in: .people)
    }

    private func addToPeople() {
        guard let connection = model.addToPeople(card, modelContext: modelContext) else { return }
        addedCount += 1
        router.present(.addContext(connectionID: connection.id))
    }

    private func saveToContacts() {
        contactDraft = ContactDraft(fullName: snapshot.fullName, jobTitle: snapshot.jobTitle,
                                    company: snapshot.company, fields: snapshot.fields)
    }

    private func contactSaved(_ saved: Bool) {
        if saved { router.showToast("Added to Contacts", systemImage: "person.crop.circle.badge.checkmark") }
    }
}

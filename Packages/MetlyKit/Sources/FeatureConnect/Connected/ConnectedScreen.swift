import MetlyCapture
import MetlyCore
import MetlyData
import SwiftData
import SwiftUI

/// CONNECTED (SPEC §2.5.27): success header, the Context Capture block (where you met auto-filled,
/// private note with voice, tags, follow-up), Add to Contacts; Save → CONNECTION_DETAIL,
/// Not Now → PEOPLE (the connection is saved either way).
struct ConnectedScreen: View {
    let connectionID: UUID

    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext

    /// Held directly: an offline-accepted connection may get the server's id after a sync.
    @State private var connection: Connection?
    @State private var hasLoaded = false
    @State private var draft = CaptureDraft()
    @State private var contactDraft: ContactDraft?
    @State private var addedToContacts = false
    @State private var showsLimitAlert = false
    @State private var limitCount = 0
    @State private var successCount = 0

    var body: some View {
        NavigationStack {
            Group {
                if let connection {
                    Form {
                        ConnectedHeaderSection(connection: connection, myCard: myCard(for: connection),
                                               profile: modelContext.currentProfile())
                        ContextCaptureForm(draft: $draft)
                        Section {
                            Button {
                                contactDraft = ContactDraft(connection: connection)
                            } label: {
                                Label(addedToContacts ? "Added to Contacts" : "Add to Contacts",
                                      systemImage: addedToContacts ? "checkmark.circle.fill" : "person.crop.circle.badge.plus")
                            }
                            .disabled(addedToContacts)
                        }
                    }
                } else if hasLoaded {
                    ContentUnavailableView("Connection Not Found", systemImage: "person.crop.circle.badge.questionmark",
                                           description: Text("It may have been removed on another device."))
                } else {
                    ProgressView()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now", action: notNow)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(connection == nil)
                }
            }
            .contactSaver(item: $contactDraft) { saved in
                guard saved else { return }
                addedToContacts = true
                successCount += 1
                router.showToast("Added to Contacts", systemImage: "person.crop.circle.badge.checkmark")
                AccessibilityNotification.Announcement("Added to Contacts").post()
            }
            .followUpLimitAlert(isPresented: $showsLimitAlert, openCount: limitCount)
        }
        .sensoryFeedback(.success, trigger: successCount)
        .task { await load() }
    }

    private var firstName: String {
        connection.map { ConnectCopy.firstName(of: $0.fullName) } ?? ""
    }

    private func myCard(for connection: Connection) -> Card? {
        if let id = connection.mySharedCardID, let card = modelContext.record(Card.self, id: id), !card.isDeleted {
            return card
        }
        return modelContext.cardToShare()
    }

    /// The connection is normally saved before CONNECTED opens; give a just-synced one a moment.
    private func load() async {
        guard !hasLoaded else { return }
        for attempt in 0..<5 {
            if let found = modelContext.record(Connection.self, id: connectionID), !found.isDeleted {
                draft = .capture(for: found, in: modelContext)
                connection = found
                successCount += 1
                break
            }
            guard attempt < 4 else { break }
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
        }
        hasLoaded = true
    }

    private func save() {
        guard let connection else { return }
        let result = draft.apply(to: connection, in: modelContext, limits: services.entitlements.limits)
        if case .limitReached(let count) = result.followUp {
            limitCount = count
            showsLimitAlert = true
            return
        }
        router.showToast(result.toastMessage(otherwise: "Connection Saved"), systemImage: "checkmark.circle")
        router.open(.connectionDetail(id: connection.id), in: .people)
    }

    private func notNow() {
        let name = firstName
        router.dismiss()
        router.select(.people)
        if !name.isEmpty {
            router.showToast("Connected with \(name)", systemImage: "person.crop.circle.badge.checkmark")
        }
    }
}

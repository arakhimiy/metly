import MetlyCore
import MetlyData
import MetlyDesign
import SwiftData
import SwiftUI

/// PEOPLE tab root (SPEC §2.5.11).
struct PeopleScreen: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext

    @Query(Connection.live) private var connections: [Connection]
    @Query(ConnectRequest.pendingIncoming) private var requests: [ConnectRequest]
    @Query(filter: #Predicate<Event> { $0.deletedAt == nil }, sort: \Event.startDate, order: .reverse)
    private var events: [Event]

    @State private var query: String
    @State private var filter: PeopleFilter
    @State private var personToRemove: Connection?
    @State private var isConfirmingRemove = false
    @State private var requestToDecline: ConnectRequest?
    @State private var isConfirmingDecline = false
    @State private var acceptedCount = 0

    init(query: String = "", filter: PeopleFilter = .all) {
        _query = State(initialValue: query)
        _filter = State(initialValue: filter)
    }

    var body: some View {
        Group {
            if connections.isEmpty && requests.isEmpty {
                if services.sync.status == .syncing {
                    PeopleSkeletonList()
                } else {
                    PeopleEmptyState(canShowQR: modelContext.cardToShare() != nil,
                                     onConnect: openConnect, onShowQR: showQR)
                }
            } else {
                PeopleList(connections: connections, requests: query.isEmpty ? requests : [],
                           events: events, query: query, filter: $filter,
                           sharedCardName: modelContext.cardToShare()?.name,
                           onAccept: accept, onDecline: confirmDecline,
                           rowActions: PersonRowActions(addNote: addNote, remove: confirmRemove))
            }
        }
        .navigationTitle("People")
        .searchable(text: $query, prompt: "Search")
        .refreshable { await services.sync.syncNow() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Connect", systemImage: "person.badge.plus", action: openConnect)
            }
        }
        .alert(removeTitle, isPresented: $isConfirmingRemove, presenting: personToRemove) { person in
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) { remove(person) }
        } message: { _ in
            Text("Your note will be deleted. They keep the card you shared.")
        }
        .alert(declineTitle, isPresented: $isConfirmingDecline, presenting: requestToDecline) { request in
            Button("Cancel", role: .cancel) {}
            Button("Decline", role: .destructive) { decline(request) }
        } message: { _ in
            Text("They won’t be notified.")
        }
        .sensoryFeedback(.success, trigger: acceptedCount)
    }

    private var removeTitle: String {
        "Remove \(PersonName.first(personToRemove?.fullName ?? ""))?"
    }

    private var declineTitle: String {
        "Decline \(PersonName.first(requestToDecline?.peerName ?? ""))’s Request?"
    }

    // MARK: Actions

    private func openConnect() {
        router.present(.connect(cardID: nil))
    }

    private func showQR() {
        guard let card = modelContext.cardToShare() else { return }
        router.present(.qr(cardID: card.id))
    }

    private func addNote(_ person: Connection) {
        router.present(.addContext(connectionID: person.id))
    }

    private func confirmRemove(_ person: Connection) {
        personToRemove = person
        isConfirmingRemove = true
    }

    private func remove(_ person: Connection) {
        let undo = PeopleActions.remove(person, in: modelContext)
        router.showToast("Connection Removed", systemImage: "trash", undo: undo)
    }

    private func accept(_ request: ConnectRequest) {
        let person = PeopleActions.accept(request, in: modelContext)
        acceptedCount += 1
        router.present(.connected(connectionID: person.id))
    }

    private func confirmDecline(_ request: ConnectRequest) {
        requestToDecline = request
        isConfirmingDecline = true
    }

    private func decline(_ request: ConnectRequest) {
        PeopleActions.decline(request, in: modelContext)
        router.showToast("Request Declined", systemImage: "xmark.circle")
    }
}

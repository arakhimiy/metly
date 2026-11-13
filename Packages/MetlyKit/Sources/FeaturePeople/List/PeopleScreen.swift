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
    @Query(ConnectRequest.pendingIncoming) private var pendingRequests: [ConnectRequest]
    @Query(filter: #Predicate<Connection> { $0.isBlocked && $0.deletedAt == nil }) private var blockedPeople: [Connection]
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

    /// Expired live requests and requests from blocked people aren't offered.
    private var requests: [ConnectRequest] {
        RequestVisibility.visible(pendingRequests, blockedUserIDs: Set(blockedPeople.compactMap(\.remoteUserID)))
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
        .toolbarTitleDisplayMode(.inlineLarge)
        .searchable(text: $query, prompt: "Search")
        .refreshable { await services.sync.syncNow() }
        .toolbar {
            // "+" means adding someone: type them in, read their paper card, or swap with someone nearby.
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Add Manually", systemImage: "square.and.pencil", action: addManually)
                    Button("Scan Paper Card", systemImage: "camera.viewfinder", action: scanPaperCard)
                    Button("Connect Nearby", systemImage: "dot.radiowaves.left.and.right", action: openConnect)
                    Section {
                        Button("Start Event", systemImage: "calendar.badge.plus") {
                            router.present(.startEvent(eventID: nil))
                        }
                    }
                } label: {
                    Label("Add Contact", systemImage: "plus")
                }
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
        String(localized: "Remove \(PersonName.first(personToRemove?.fullName ?? ""))?", bundle: .appStrings)
    }

    private var declineTitle: String {
        String(localized: "Decline \(PersonName.first(requestToDecline?.peerName ?? ""))’s Request?", bundle: .appStrings)
    }

    // MARK: Actions

    private func openConnect() {
        router.present(.connect(cardID: nil))
    }

    /// An empty contact form (the paper card review without a photo).
    private func addManually() {
        router.push(.paperReview(PaperCardDraft()))
    }

    private func scanPaperCard() {
        router.select(.scan)
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
        router.showToast(String(localized: "Connection Removed", bundle: .appStrings), systemImage: "trash", undo: undo)
    }

    private func accept(_ request: ConnectRequest) {
        let blocked = Set(blockedPeople.compactMap(\.remoteUserID))
        guard RequestVisibility.isAnswerable(request, blockedUserIDs: blocked) else {
            router.showToast(String(localized: "This request has expired", bundle: .appStrings), systemImage: "clock.badge.xmark")
            return
        }
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
        router.showToast(String(localized: "Request Declined", bundle: .appStrings), systemImage: "xmark.circle")
    }
}

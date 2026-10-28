#if DEBUG
import MetlyCore
import MetlyData
import MetlyNetworking
import SwiftData
import SwiftUI

/// Sample Nearby people from the mock world (same people the demo transport finds).
enum ConnectPreviewData {
    static var people: [NearbyPerson] {
        MockSeed.peers.filter { !$0.isPaused }.map { NearbyPerson($0.nearby) }
    }

    static var kamila: NearbyPerson { people[0] }
    static var nodira: NearbyPerson { people[people.count - 1] }

    static func model(_ mode: ConnectMode = .nearby, phase: ConnectMachine.Phase = .discovering,
                      notice: ConnectMachine.Notice? = nil, people: [NearbyPerson] = [],
                      availability: ConnectAvailability = .active, hasWaitedForPeers: Bool = false,
                      tapStatus: TapStatus = .ready, tapCapability: TapCapability = .preciseDistance) -> ConnectModel {
        let isActive = availability == .active
        let machine = ConnectMachine(phase: isActive ? phase : .idle, notice: notice, isDiscoveryActive: isActive)
        return ConnectModel(previewMode: mode, machine: machine, peers: people, availability: availability,
                            hasWaitedForPeers: hasWaitedForPeers, tapStatus: tapStatus, tapCapability: tapCapability)
    }
}

/// CONNECT with the seeded incoming request (Bekzod) on top.
struct IncomingRequestPreviewHost: View {
    let model: ConnectModel
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ConnectScreen(requestedCardID: nil, model: model)
            .task {
                if let request = try? modelContext.fetch(ConnectRequest.pendingIncoming).first {
                    model.present(request)
                }
            }
    }
}

/// Inserts a fresh connection (no event) into the preview store, then shows CONNECTED for it.
struct ConnectedPreviewHost: View {
    /// Extra numbers they shared (work, home…).
    var additionalPhones: [LabeledPhone] = []

    @Environment(\.modelContext) private var modelContext
    @State private var connectionID: UUID?

    var body: some View {
        Group {
            if let connectionID {
                ConnectedView(connectionID: connectionID)
            } else {
                ProgressView()
            }
        }
        .task {
            let peer = MockSeed.peers[2]
            let person = Connection(fullName: peer.fullName, jobTitle: peer.jobTitle, company: peer.company,
                                    source: .nearby, context: MeetingContext(metAt: .now))
            person.remoteUserID = peer.userID
            person.theirCard = peer.card
            for field in peer.fields where field.privacy != .private {
                person.setValue(field.value, for: field.kind)
            }
            person.additionalPhones = additionalPhones
            person.mySharedCardID = modelContext.defaultCard()?.id
            modelContext.insert(person)
            try? modelContext.save()
            connectionID = person.id
        }
    }
}
#endif

import SwiftUI

/// Nearby mode (SPEC §2.5.26): searching hero → live "Nearby on Tanishly" list with Connect /
/// Waiting… → "No One Nearby Yet" after ~10 s. Emits list `Section`s.
struct NearbySections: View {
    let model: ConnectModel
    let onShowQR: (() -> Void)?

    var body: some View {
        if model.peers.isEmpty {
            if model.showsNoOneNearby {
                Section {
                    VStack(spacing: 20) {
                        ConnectUnavailableView(reason: .noOneNearby, onShowQR: onShowQR)
                        NearbyTipsView()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.bottom, 8)
                }
            } else {
                Section {
                    SearchingHeader(isSearching: model.machine.isDiscoveryActive)
                }
                .listRowBackground(Color.clear)
            }
        } else {
            Section {
                ForEach(model.peers.people) { person in
                    NearbyPersonRow(person: person, status: status(for: person),
                                    onConnect: { model.connect(to: person) },
                                    onCancel: model.cancelRequest)
                }
            } header: {
                NearbySectionHeader(isSearching: model.machine.isDiscoveryActive)
            } footer: {
                Text("Only people with Connect open and Show in Nearby on appear here.")
            }
        }
    }

    private func status(for person: NearbyPerson) -> NearbyPersonRow.Status {
        if model.machine.waitingPeer?.userID == person.userID { return .waiting }
        return .ready(canConnect: model.machine.canSendRequest)
    }
}

import MetlyCore
import MetlyData
import SwiftUI

/// SCANNED_CARD (SPEC §2.5.9): loads the scanned Metly card (or reads a foreign vCard) and
/// shows it with Connect / Add to People / Save to Contacts.
struct ScannedCardScreen: View {
    let payload: ScannedCardPayload

    @Environment(MetlyClient.self) private var client
    @State private var model: ScannedCardModel
    @State private var loadAttempt = 0
    private let loadsOnAppear: Bool

    /// `previewPhase` / `previewConnectPhase` show a fixed state without loading (previews).
    init(payload: ScannedCardPayload, previewPhase: ScannedCardModel.Phase? = nil,
         previewConnectPhase: ScannedCardModel.ConnectPhase = .idle) {
        self.payload = payload
        _model = State(initialValue: ScannedCardModel(phase: previewPhase ?? .loading, connectPhase: previewConnectPhase))
        loadsOnAppear = previewPhase == nil
    }

    var body: some View {
        content
            .navigationTitle("Scanned Card")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: loadAttempt) {
                guard loadsOnAppear || loadAttempt > 0 else { return }
                await model.load(payload, client: client)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView("Loading Card…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .metly(let card):
            if let snapshot = card.snapshot {
                MetlyCardDetail(card: card, snapshot: snapshot, model: model)
            }
        case .contact(let contact):
            ContactCardDetail(contact: contact, model: model)
        case .unavailable:
            ContentUnavailableView {
                Label("Card Unavailable", systemImage: "rectangle.on.rectangle.slash")
            } description: {
                Text("This card isn’t available right now. The link may be paused or removed — ask the person for a new one.")
            }
        case .offline:
            ContentUnavailableView {
                Label("You’re Offline", systemImage: "wifi.slash")
            } description: {
                Text("Connect to the internet to see this card.")
            } actions: {
                Button("Try Again", action: retry)
            }
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn’t Load the Card", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again", action: retry)
            }
        case .unreadableContact:
            ContentUnavailableView {
                Label("Couldn’t Read This Contact", systemImage: "person.crop.circle.badge.exclamationmark")
            } description: {
                Text("The QR code holds a contact card without a name or contact details.")
            }
        }
    }

    private func retry() {
        loadAttempt += 1
    }
}

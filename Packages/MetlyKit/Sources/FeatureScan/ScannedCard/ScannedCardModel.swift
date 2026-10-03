import Foundation
import MetlyCardKit
import MetlyCore
import MetlyData
import MetlyNetworking
import Observation
import SwiftData

/// Loads what was scanned and runs SCANNED_CARD's actions (Connect, Add to People).
@Observable
final class ScannedCardModel {
    enum Phase: Equatable {
        case loading
        /// Someone's Metly card (public profile).
        case metly(PublicCardDTO)
        /// A foreign vCard (SPEC §9 Q41).
        case contact(PaperCardDraft)
        /// Paused, deleted or unknown slug.
        case unavailable
        case offline
        case failed(String)
        /// A vCard without anything usable.
        case unreadableContact
    }

    /// Connect request progress (PLAN Q8: the other side accepts).
    enum ConnectPhase: Equatable {
        case idle
        case sending
        case waiting
        /// Pending past our wait: they'll get it in People and can accept later.
        case requestSent
        /// Expired / declined (never shown as "declined" — PLAN Q9).
        case noResponse
        /// Offline: saved locally as a connection; Connect again later.
        case savedOffline
        case accepted
    }

    /// How long SCANNED_CARD waits for an answer before saying "Request Sent".
    static let connectWait: Duration = .seconds(15)

    var phase: Phase
    var connectPhase: ConnectPhase = .idle
    var errorMessage: String?
    var showsError = false
    /// Set by Cancel so the request is withdrawn (leaving the screen keeps it pending).
    @ObservationIgnored var withdrawsOnCancel = false

    init(phase: Phase = .loading, connectPhase: ConnectPhase = .idle) {
        self.phase = phase
        self.connectPhase = connectPhase
    }

    // MARK: Loading

    func load(_ payload: ScannedCardPayload, client: MetlyClient) async {
        if let vCard = payload.vCard {
            phase = VCardParser.parse(vCard).map(Phase.contact) ?? .unreadableContact
            return
        }
        guard let slug = payload.slug ?? payload.url.flatMap({ QRPayloadClassifier.metlySlug(in: $0.absoluteString) }) else {
            phase = .unavailable
            return
        }
        phase = .loading
        do {
            let card = try await client.publicProfile(slug: slug)
            phase = card.status == .available && card.snapshot != nil ? .metly(card) : .unavailable
        } catch APIError.offline {
            phase = .offline
        } catch let error as APIError where error.code == .notFound || error.statusCode == 404 {
            phase = .unavailable
        } catch is CancellationError {
            return
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: Connect

    /// Sends a connect request and waits briefly for the answer. Accepted → CONNECTED;
    /// offline → saved locally (source `.scanQR`) and ADD_CONTEXT opens.
    func connect(to card: PublicCardDTO, client: MetlyClient, modelContext: ModelContext, router: AppRouter) async {
        guard let snapshot = card.snapshot else { return }
        guard let cardID = modelContext.cardToShare()?.id else {
            fail("Create a card first — it’s what \(card.owner?.firstName ?? "they") will get back.")
            return
        }
        withdrawsOnCancel = false
        connectPhase = .sending
        let request: ConnectRequestDTO
        do {
            request = try await client.sendConnectRequest(to: .slug(card.slug), cardID: cardID, method: .scan)
        } catch APIError.offline {
            let connection = ScanConnectionFactory.insertConnection(from: snapshot, remoteUserID: card.owner?.userID,
                                                                    sharedCardID: cardID, in: modelContext)
            connectPhase = .savedOffline
            router.present(.addContext(connectionID: connection.id))
            return
        } catch {
            connectPhase = .idle
            // Cancelled (Cancel tapped or the screen closed) isn't an error worth showing.
            if !Task.isCancelled, !(error is CancellationError) { fail(error.localizedDescription) }
            return
        }

        connectPhase = .waiting
        let outcome = await Self.outcome(of: request, client: client, waitingAtMost: Self.connectWait)
        if Task.isCancelled {
            if withdrawsOnCancel {
                // A fresh task: this one is cancelled, but the withdrawal must still reach the server.
                Task { await client.cancel(request) }
            }
            connectPhase = .idle
            return
        }
        switch outcome {
        case .accepted(let connectionID):
            connectPhase = .accepted
            router.present(.connected(connectionID: connectionID))
        case .noResponse:
            connectPhase = .noResponse
        case .cancelled:
            connectPhase = .idle
        case nil:
            connectPhase = .requestSent
        }
    }

    /// The request's outcome, or nil when it is still pending after `limit` (scan requests live
    /// for days; the person may accept later from People).
    static func outcome(of request: ConnectRequestDTO, client: MetlyClient, waitingAtMost limit: Duration) async -> ConnectOutcome? {
        await withTaskGroup(of: ConnectOutcome?.self) { group in
            group.addTask { await client.outcome(of: request) }
            group.addTask {
                try? await Task.sleep(for: limit)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private func fail(_ message: String) {
        errorMessage = message
        showsError = true
    }

    // MARK: Add to People

    /// "Add to People" without a request: a `.scanQR` connection from their public card.
    func addToPeople(_ card: PublicCardDTO, modelContext: ModelContext) -> Connection? {
        guard let snapshot = card.snapshot else { return nil }
        return ScanConnectionFactory.insertConnection(from: snapshot, remoteUserID: card.owner?.userID, in: modelContext)
    }

    /// vCard "Add to People".
    func addToPeople(_ contact: PaperCardDraft, modelContext: ModelContext) -> Connection {
        ScanConnectionFactory.insertConnection(from: contact, source: .scanQR, in: modelContext)
    }
}

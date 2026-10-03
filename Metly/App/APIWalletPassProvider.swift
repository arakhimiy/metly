import FeatureCards
import Foundation
import MetlyData
import SwiftData

/// Wallet passes are signed by the server (`GET /v1/cards/{id}/wallet-pass`).
@MainActor
struct APIWalletPassProvider: WalletPassProviding {
    let client: MetlyClient
    let container: ModelContainer

    func passData(for cardID: UUID) async throws -> Data {
        guard let card = container.mainContext.record(Card.self, id: cardID) else { throw WalletPassError.invalidPass }
        return try await client.walletPass(for: card)
    }
}

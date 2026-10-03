import Foundation
import SwiftUI

/// Supplies the signed `.pkpass` for a card (`GET /v1/cards/{id}/wallet-pass`, SPEC §5.3).
/// Passes are signed with the Pass Type ID certificate on the server, so the app can't make them itself.
///
/// The app injects the API-backed implementation once at the root:
/// ```swift
/// .environment(\.walletPassProvider, APIWalletPassProvider(client: api))
/// ```
@MainActor
public protocol WalletPassProviding: Sendable {
    func passData(for cardID: UUID) async throws -> Data
}

/// Default until the API is wired: every request fails with `WalletPassError.serverRequired`.
public struct ServerRequiredWalletPassProvider: WalletPassProviding {
    public nonisolated init() {}

    public func passData(for cardID: UUID) async throws -> Data {
        throw WalletPassError.serverRequired
    }
}

public enum WalletPassError: LocalizedError, Equatable {
    /// No server connection is available to sign the pass.
    case serverRequired
    /// `PKAddPassesViewController.canAddPasses()` is false (e.g. some iPads, restrictions).
    case cannotAddPasses
    /// The data isn't a valid signed pass.
    case invalidPass

    public var errorDescription: String? {
        switch self {
        case .serverRequired: String(localized: "Wallet passes need the server. Try again when you’re online.")
        case .cannotAddPasses: String(localized: "This device can’t add passes to Apple Wallet.")
        case .invalidPass: String(localized: "The pass couldn’t be read. Try again in a moment.")
        }
    }
}

public extension EnvironmentValues {
    /// Wallet pass source used by SHARE_SHEET and CARD_EXPORT.
    @Entry var walletPassProvider: any WalletPassProviding = ServerRequiredWalletPassProvider()
}

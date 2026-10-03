import Foundation
import Observation
import PassKit

/// Fetches a card's pass and hands it to `PKAddPassesViewController` (see `.walletAddFlow(_:)`).
@MainActor
@Observable
final class WalletAddFlow {
    /// The pass waiting to be reviewed in the system "Add to Wallet" sheet.
    var pendingPass: WalletPassItem?
    var errorMessage: String?
    private(set) var isLoading = false
    /// Bumped when a pass was really added (drives haptics and inline confirmation).
    private(set) var addedCount = 0

    var isShowingError: Bool {
        get { errorMessage != nil }
        set { if !newValue { errorMessage = nil } }
    }

    func start(cardID: UUID, provider: any WalletPassProviding) async {
        guard !isLoading else { return }
        guard PKAddPassesViewController.canAddPasses() else {
            errorMessage = WalletPassError.cannotAddPasses.errorDescription
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let data = try await provider.passData(for: cardID)
            pendingPass = WalletPassItem(pass: try PKPass(data: data))
        } catch let error as WalletPassError {
            errorMessage = error.errorDescription
        } catch let error as PKPassKitError where error.code == .invalidDataError || error.code == .invalidSignature {
            errorMessage = WalletPassError.invalidPass.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func finish(added: Bool) {
        pendingPass = nil
        if added { addedCount += 1 }
    }
}

/// Identifiable wrapper so a pass can drive `.sheet(item:)`.
struct WalletPassItem: Identifiable {
    let id = UUID()
    let pass: PKPass
}

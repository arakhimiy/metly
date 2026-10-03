import Foundation
import MetlyCore
import StoreKit
import UIKit

/// Keeps `services.entitlements` in sync with StoreKit 2.
///
/// The app creates one instance at launch and keeps it for the app's lifetime:
/// ```swift
/// let subscriptionManager = SubscriptionManager()
/// subscriptionManager.start(services: services)
/// ```
/// It listens to `Transaction.updates` (renewals, refunds, Ask to Buy approvals, purchases made on
/// other devices), re-evaluates `Transaction.currentEntitlements` at launch and whenever the app
/// becomes active, finishes transactions and forwards their JWS to the backend
/// (`services.subscriptions.verify`), ignoring failures (offline-first).
@MainActor
public final class SubscriptionManager {
    private var tasks: [Task<Void, Never>] = []

    public init() {}

    public var isRunning: Bool { !tasks.isEmpty }

    /// Starts listening. Safe to call more than once (later calls are ignored).
    public func start(services: AppServices) {
        guard tasks.isEmpty else { return }
        tasks = [
            Task { await Self.refreshEntitlements(services: services, verifyWithServer: true) },
            Task { await Self.listenForTransactionUpdates(services: services) },
            Task { await Self.refreshWhenActive(services: services) },
        ]
    }

    public func stop() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }

    // MARK: Entitlements

    /// Re-reads `Transaction.currentEntitlements` and updates `services.entitlements`.
    /// - Parameters:
    ///   - verifyWithServer: also forwards each entitlement's JWS to the backend.
    ///   - additional: records known to be valid but possibly not yet visible in `currentEntitlements`
    ///     (a purchase that just completed).
    public static func refreshEntitlements(services: AppServices, verifyWithServer: Bool = false) async {
        await refreshEntitlements(services: services, verifyWithServer: verifyWithServer, additional: [])
    }

    static func refreshEntitlements(services: AppServices, verifyWithServer: Bool, additional: [SubscriptionRecord]) async {
        var records = additional
        var signedTransactions: [String] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, ProProduct(productID: transaction.productID) != nil else { continue }
            records.append(await record(for: transaction))
            signedTransactions.append(result.jwsRepresentation)
        }
        apply(EntitlementMapper.snapshot(from: records, now: .now), to: services.entitlements)

        guard verifyWithServer else { return }
        for jws in signedTransactions {
            await forwardToServer(jws, services: services)
        }
    }

    /// Handles a purchase completed in the paywall (StoreKit views return it directly instead of
    /// routing it through `Transaction.updates`). Returns false when the transaction failed verification.
    @discardableResult
    static func processPurchase(_ verification: VerificationResult<Transaction>, services: AppServices) async -> Bool {
        guard case .verified(let transaction) = verification else { return false }
        let purchased = await record(for: transaction)
        await refreshEntitlements(services: services, verifyWithServer: false, additional: [purchased])
        await transaction.finish()
        await forwardToServer(verification.jwsRepresentation, services: services)
        return true
    }

    /// Writes a snapshot into `Entitlements`, touching only the values that changed
    /// (Observation notifies on every assignment).
    static func apply(_ snapshot: EntitlementSnapshot, to entitlements: Entitlements) {
        let plan: Plan = snapshot.isPro ? .pro : .free
        if entitlements.plan != plan { entitlements.plan = plan }
        if entitlements.productID != snapshot.productID { entitlements.productID = snapshot.productID }
        if entitlements.renewsAt != snapshot.renewsAt { entitlements.renewsAt = snapshot.renewsAt }
        if entitlements.willRenew != snapshot.willRenew { entitlements.willRenew = snapshot.willRenew }
    }

    // MARK: Listeners

    private static func listenForTransactionUpdates(services: AppServices) async {
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result else { continue }
            await refreshEntitlements(services: services)
            await transaction.finish()
            if ProProduct(productID: transaction.productID) != nil {
                await forwardToServer(result.jwsRepresentation, services: services)
            }
        }
    }

    /// Expirations don't always arrive as transaction updates — re-check when the app comes back.
    private static func refreshWhenActive(services: AppServices) async {
        for await _ in NotificationCenter.default.notifications(named: UIApplication.didBecomeActiveNotification) {
            await refreshEntitlements(services: services)
        }
    }

    // MARK: Helpers

    private static func forwardToServer(_ jws: String, services: AppServices) async {
        // Offline-first: StoreKit is the local source of truth; the server catches up on the next launch.
        _ = try? await services.subscriptions.verify(signedTransaction: jws)
    }

    private static func record(for transaction: Transaction) async -> SubscriptionRecord {
        var record = SubscriptionRecord(
            productID: transaction.productID,
            purchaseDate: transaction.purchaseDate,
            expirationDate: transaction.expirationDate,
            revocationDate: transaction.revocationDate,
            isUpgraded: transaction.isUpgraded
        )
        if let status = await transaction.subscriptionStatus {
            record.state = SubscriptionRecord.RenewalState(status.state)
            if case .verified(let renewalInfo) = status.renewalInfo {
                record.willAutoRenew = renewalInfo.willAutoRenew
                record.renewalDate = renewalInfo.renewalDate
                record.gracePeriodExpirationDate = renewalInfo.gracePeriodExpirationDate
            }
        }
        return record
    }
}

nonisolated extension SubscriptionRecord.RenewalState {
    init?(_ state: Product.SubscriptionInfo.RenewalState) {
        switch state {
        case .subscribed: self = .subscribed
        case .inGracePeriod: self = .inGracePeriod
        case .inBillingRetryPeriod: self = .inBillingRetryPeriod
        case .expired: self = .expired
        case .revoked: self = .revoked
        default: return nil
        }
    }
}

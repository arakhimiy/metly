import Foundation
import MetlyCore
import MetlyData
import SwiftData

/// Answers a connect request from its push ("Accept" / "Decline" on the notification). The request
/// may not be on the device yet, so pending requests are pulled first. Accept shares the card to
/// share and lands on CONNECTED, like the in-app banner.
@MainActor
public enum ConnectRequestResponder {
    public static func answer(requestID: UUID, accept: Bool, client: MetlyClient, context: ModelContext, router: AppRouter) async {
        try? await client.refreshIncomingRequests()
        let blocked = ConnectModel.blockedUserIDs(in: context)
        guard let request = context.record(ConnectRequest.self, id: requestID),
              IncomingRequestBannerPolicy.isAnswerable(request, blockedUserIDs: blocked, now: .now) else {
            if accept { router.showToast(String(localized: "This request has expired", bundle: .appStrings), systemImage: "clock.badge.xmark") }
            return
        }
        do {
            if accept {
                guard let cardID = request.myCardID ?? context.cardToShare()?.id else {
                    router.showToast(String(localized: "Create a card first, then accept.", bundle: .appStrings), systemImage: "rectangle.stack.badge.plus")
                    return
                }
                let connection = try await client.accept(request, sharing: cardID)
                    ?? OfflineAccept.connection(for: request, sharing: cardID, in: context)
                router.present(.connected(connectionID: connection.id))
            } else {
                try await client.decline(request)
            }
        } catch {
            if accept { router.showToast(error.localizedDescription, systemImage: "exclamationmark.triangle") }
        }
    }
}

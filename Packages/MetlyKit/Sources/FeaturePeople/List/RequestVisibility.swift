import Foundation
import MetlyData

/// Which pending requests People › Requests offers (`ConnectRequest.pendingIncoming` is only the raw cache).
public enum RequestVisibility {
    /// Answerable requests, newest first, one per person: not expired (live Nearby / Tap Phones requests
    /// last 60 s and may sit in the cache after that) and not from someone the owner blocked.
    public static func visible(_ requests: [ConnectRequest], blockedUserIDs: Set<UUID>, now: Date = .now) -> [ConnectRequest] {
        var seenPeers = Set<UUID>()
        return requests
            .filter { isAnswerable($0, blockedUserIDs: blockedUserIDs, now: now) }
            .sorted { $0.createdAt > $1.createdAt }
            .filter { seenPeers.insert($0.peerUserID).inserted }
    }

    public static func isAnswerable(_ request: ConnectRequest, blockedUserIDs: Set<UUID>, now: Date = .now) -> Bool {
        request.direction == .incoming && request.status == .pending && !request.isDeleted
            && !blockedUserIDs.contains(request.peerUserID)
            && (request.expiresAt.map { $0 > now } ?? true)
    }
}

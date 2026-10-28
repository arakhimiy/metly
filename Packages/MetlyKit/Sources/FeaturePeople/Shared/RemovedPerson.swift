import Foundation
import MetlyData
import MetlyNetworking
import SwiftData

/// What "Remove" took away, kept as values so Undo still works after the sync engine hard-deleted the
/// records (server confirmed the tombstone; the person's follow-ups cascade with it).
struct RemovedPerson {
    private let person: ConnectionDTO
    private let avatarData: Data?
    /// Every follow-up the person had (open ones are tombstoned by Remove; done ones go with the cascade).
    private let followUps: [FollowUpDTO]

    init(_ person: Connection) {
        self.person = person.dto
        avatarData = person.avatarData
        followUps = person.followUps.filter { !$0.isDeleted }.map(\.dto)
    }

    /// Brings the person and their follow-ups back with the same ids, as fresh edits
    /// (newer than the tombstone, so the server resurrects them).
    func restore(in context: ModelContext) {
        let restored: Connection
        if let live = context.record(Connection.self, id: person.id) {
            restored = live
            if live.isDeleted { live.restore() }
        } else {
            var dto = person
            dto.deletedAt = nil
            restored = Connection(dto: dto, in: context)
            restored.avatarData = avatarData
            restored.markChanged()
        }

        for followUp in followUps {
            if let live = context.record(FollowUp.self, id: followUp.id) {
                if live.isDeleted { live.restore() }
            } else {
                var dto = followUp
                dto.deletedAt = nil
                let recreated = FollowUp(dto: dto, in: context)
                recreated.connection = restored
                recreated.markChanged()
            }
        }
    }
}

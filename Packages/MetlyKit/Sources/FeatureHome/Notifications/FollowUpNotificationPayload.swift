import Foundation
import MetlyCore
import UserNotifications

/// Everything needed to schedule one PUSH_FOLLOWUP local notification. Pure value so the
/// identifier / content rules are testable without UserNotifications.
nonisolated struct FollowUpNotificationPayload: Equatable, Sendable {
    static let identifierPrefix = "followup."
    static let threadIdentifier = "follow-ups"

    enum UserInfoKey {
        static let followUpID = "followUpID"
        static let link = "link"
        static let fingerprint = "fingerprint"
    }

    let followUpID: UUID
    let identifier: String
    /// "{Full name}".
    let title: String
    /// "{what} · via {channel}".
    let body: String
    let categoryIdentifier: String
    let fireDate: Date
    /// `nameshake://reminder/{id}` — the same link widgets use.
    let link: URL
    /// Changes whenever anything visible, the fire date or the time zone changes (skip re-adding
    /// unchanged requests). The trigger is wall-clock time in the zone it was built in, so a request
    /// from another zone is stale even when the due moment is the same.
    let fingerprint: String

    /// - Parameter hasChannelValue: whether the person has a usable value for `channel`
    ///   (decides between the category with "Open {channel}" and the plain one).
    /// - Parameter timeZone: the zone `makeRequest(calendar:)` computes the wall-clock trigger in.
    init(followUpID: UUID, personName: String, what: String, channel: FollowUpChannel,
         hasChannelValue: Bool, dueAt: Date, timeZone: TimeZone = .current) {
        self.followUpID = followUpID
        identifier = Self.identifier(for: followUpID)
        let name = personName.trimmingCharacters(in: .whitespacesAndNewlines)
        title = name.isEmpty ? String(localized: "Follow up", bundle: .appStrings) : name
        let task = what.trimmingCharacters(in: .whitespacesAndNewlines)
        body = String(localized: "\(task.isEmpty ? String(localized: "Follow up") : task) · via \(channel.title)", bundle: .appStrings)
        categoryIdentifier = FollowUpNotificationCategory.identifier(for: hasChannelValue ? channel : nil)
        fireDate = dueAt
        link = URL(string: "\(Brand.urlScheme)://reminder/\(followUpID.uuidString)")!
        fingerprint = "\(title)|\(body)|\(categoryIdentifier)|\(Int(dueAt.timeIntervalSince1970))|\(timeZone.identifier)"
    }

    static func identifier(for followUpID: UUID) -> String {
        identifierPrefix + followUpID.uuidString
    }

    static func followUpID(fromIdentifier identifier: String) -> UUID? {
        guard identifier.hasPrefix(identifierPrefix) else { return nil }
        return UUID(uuidString: String(identifier.dropFirst(identifierPrefix.count)))
    }

    var userInfo: [String: String] {
        [
            UserInfoKey.followUpID: followUpID.uuidString,
            UserInfoKey.link: link.absoluteString,
            UserInfoKey.fingerprint: fingerprint,
        ]
    }

    /// Wall-clock trigger components in `calendar`'s time zone (rescheduled when the zone changes).
    func dateComponents(calendar: Calendar) -> DateComponents {
        calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
    }

    func makeRequest(calendar: Calendar = .current) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        content.threadIdentifier = Self.threadIdentifier
        content.userInfo = userInfo
        content.targetContentIdentifier = link.absoluteString
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents(calendar: calendar), repeats: false)
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }
}

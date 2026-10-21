import Foundation

/// Product constants. Never hard-code the domain or app name elsewhere.
public enum Brand {
    public static let appName = "Metly"
    public static let proName = "Metly Pro"
    public static let linkHost = "metly.link"
    public static let supportEmail = "support@metly.link"
    public static let telegramBot = "MetlyRemindBot"
    /// From `MetlyAppGroup` in the app's and the widget's Info.plist (`METLY_APP_GROUP` build setting),
    /// so a personal-team Debug build can use its own group. Tests and previews get the release group.
    public static let appGroup = Bundle.main.object(forInfoDictionaryKey: "MetlyAppGroup") as? String
        ?? "group.com.metly.app"
    public static let urlScheme = "metly"

    public static let termsURL = URL(string: "https://metly.link/terms")!
    public static let privacyURL = URL(string: "https://metly.link/privacy")!
    public static let helpURL = URL(string: "https://metly.link/help")!

    public static func cardURL(slug: String) -> URL {
        URL(string: "https://\(linkHost)/c/\(slug)")!
    }

    /// Extracts the slug from `https://metly.link/c/{slug}` (also accepts `metly://c/{slug}`).
    public static func slug(from url: URL) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        if url.host() == linkHost, parts.count == 2, parts[0] == "c" { return parts[1] }
        if url.scheme == urlScheme, url.host() == "c", let first = parts.first { return first }
        return nil
    }
}

/// Free vs Pro limits (SPEC §1.3).
public struct PlanLimits: Sendable, Equatable {
    public var maxCards: Int?
    public var maxOpenFollowUps: Int?
    public var maxActiveEvents: Int?
    public var allowsProTemplates: Bool
    public var allowsEventExport: Bool

    public static let free = PlanLimits(maxCards: 2, maxOpenFollowUps: 5, maxActiveEvents: 1,
                                        allowsProTemplates: false, allowsEventExport: false)
    public static let pro = PlanLimits(maxCards: nil, maxOpenFollowUps: nil, maxActiveEvents: nil,
                                       allowsProTemplates: true, allowsEventExport: true)

    public func allows(count: Int, of limit: KeyPath<PlanLimits, Int?>) -> Bool {
        guard let max = self[keyPath: limit] else { return true }
        return count < max
    }
}

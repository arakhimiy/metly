import Foundation

/// Product constants. Never hard-code the domain or app name elsewhere.
public enum Brand {
    public static let appName = "Nameshake"
    public static let proName = "Nameshake Pro"
    /// Host of card links and web pages, from `MetlyWebHost` (`METLY_WEB_HOST` build setting). Builds made
    /// before the domain exists point it at the API host; tests and previews get the release domain.
    public static let linkHost = (Bundle.main.object(forInfoDictionaryKey: "MetlyWebHost") as? String)
        .flatMap { $0.isEmpty ? nil : $0 } ?? "tanishly.app"
    public static let supportEmail = "support@tanishly.app"
    /// From `MetlyAppGroup` in the app's and the widget's Info.plist (`METLY_APP_GROUP` build setting),
    /// so a personal-team Debug build can use its own group. Tests and previews get the release group.
    public static let appGroup = Bundle.main.object(forInfoDictionaryKey: "MetlyAppGroup") as? String
        ?? "group.app.tanishly.ios"
    public static let urlScheme = "tanishly"

    public static let termsURL = URL(string: "https://\(linkHost)/terms")!
    public static let privacyURL = URL(string: "https://\(linkHost)/privacy")!
    public static let helpURL = URL(string: "https://\(linkHost)/help")!

    public static func cardURL(slug: String) -> URL {
        URL(string: "https://\(linkHost)/c/\(slug)")!
    }

    /// Extracts the slug from `https://tanishly.app/c/{slug}` (also accepts `tanishly://c/{slug}`).
    public static func slug(from url: URL) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        if url.host() == linkHost, parts.count == 2, parts[0] == "c" { return parts[1] }
        if url.scheme == urlScheme, url.host() == "c", let first = parts.first { return first }
        #if DEBUG
        // A local backend serves card pages from its own host (e.g. http://my-mac.local:3000/c/{slug}).
        if ["http", "https"].contains(url.scheme ?? ""), parts.count == 2, parts[0] == "c" { return parts[1] }
        #endif
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

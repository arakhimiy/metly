import Foundation
import MetlyCore

/// Namespace for the API layer (owned by the Data & Sync agent).
public enum MetlyNetworking {
    public static let defaultBaseURL = URL(string: "https://api.metly.link")!

    /// Info.plist key holding the API base URL (`$(METLY_API_BASE_URL)` build setting).
    public static let baseURLInfoKey = "MetlyAPIBaseURL"

    /// The configured backend, or nil → run against `MockMetlyServer`.
    ///
    /// Resolution order: `-MetlyAPIBaseURL https://…` launch argument / user default, then the
    /// Info.plist value. Empty strings and unresolved `$(…)` build variables mean "no backend yet".
    /// `-MetlyUseMockServer` forces the mock.
    public static func configuredBaseURL(bundle: Bundle = .main, defaults: UserDefaults = .standard,
                                         arguments: [String] = ProcessInfo.processInfo.arguments) -> URL? {
        if arguments.contains("-MetlyUseMockServer") { return nil }
        let candidates = [defaults.string(forKey: baseURLInfoKey), bundle.object(forInfoDictionaryKey: baseURLInfoKey) as? String]
        for candidate in candidates {
            if let url = parseBaseURL(candidate) { return url }
        }
        return nil
    }

    static func parseBaseURL(_ raw: String?) -> URL? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty, !raw.contains("$(") else { return nil }
        guard let url = URL(string: raw), let scheme = url.scheme, ["https", "http"].contains(scheme), url.host() != nil else { return nil }
        return url
    }
}

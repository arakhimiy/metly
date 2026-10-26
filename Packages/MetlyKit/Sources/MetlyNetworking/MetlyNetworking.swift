import Foundation
import MetlyCore

/// Namespace for the API layer (owned by the Data & Sync agent).
public enum MetlyNetworking {
    public static let defaultBaseURL = URL(string: "https://api.tanishly.app")!

    /// Info.plist key holding the API base URL (`$(METLY_API_BASE_URL)` build setting).
    public static let baseURLInfoKey = "MetlyAPIBaseURL"

    /// The configured backend, or nil → run against `MockMetlyServer`.
    ///
    /// Resolution order: `-MetlyAPIBaseURL https://…` launch argument / user default, then the
    /// Info.plist value. Empty strings and unresolved `$(…)` build variables mean "no backend yet".
    /// `-MetlyUseMockServer` forces the mock. Both overrides are Debug-only: a Release build always
    /// talks to the backend baked into its Info.plist (the Release build phase refuses to build without one).
    public static func configuredBaseURL(bundle: Bundle = .main, defaults: UserDefaults = .standard,
                                         arguments: [String] = ProcessInfo.processInfo.arguments) -> URL? {
        #if DEBUG
        if arguments.contains("-MetlyUseMockServer") {
            defaults.removeObject(forKey: baseURLInfoKey)
            return nil
        }
        // A device launched once with `-MetlyAPIBaseURL http://my-mac.local:3000` keeps that backend for
        // later launches from the Home Screen (which carry no arguments).
        if let flag = arguments.firstIndex(of: "-\(baseURLInfoKey)"), arguments.indices.contains(flag + 1),
           parseBaseURL(arguments[flag + 1]) != nil {
            defaults.set(arguments[flag + 1], forKey: baseURLInfoKey)
        }
        let candidates = [defaults.string(forKey: baseURLInfoKey), bundle.object(forInfoDictionaryKey: baseURLInfoKey) as? String]
        #else
        let candidates = [bundle.object(forInfoDictionaryKey: baseURLInfoKey) as? String]
        #endif
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

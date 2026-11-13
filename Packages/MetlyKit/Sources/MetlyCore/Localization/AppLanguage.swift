import Foundation
import ObjectiveC

/// The languages the app ships (`Localizable.xcstrings`: uz, ru, en).
public enum AppLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case uz, ru, en

    public var id: String { rawValue }

    /// The language's own name. Never translated: people look for their language written their way.
    public var nativeName: String {
        switch self {
        case .uz: "O‘zbekcha"
        case .ru: "Русский"
        case .en: "English"
        }
    }

    public var locale: Locale { Locale(identifier: rawValue) }

    /// `key` from the catalog in this language, whatever language the app is in: the language
    /// screen speaks the language being picked before it is applied. Keys used here are listed in
    /// the catalog with `extractionState: manual` (no `String(localized:)` call site to extract).
    public func localized(_ key: String) -> String {
        guard let path = Bundle.main.path(forResource: rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    /// First of the device's languages that the app ships, else Uzbek (the home market).
    public static func matching(_ preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        for identifier in preferredLanguages {
            let code = Locale(identifier: identifier).language.languageCode?.identifier.lowercased()
            if let language = code.flatMap(AppLanguage.init(rawValue:)) { return language }
        }
        return .uz
    }

    // MARK: - The app's language

    /// The language the person picked in the app, nil until they pick one (language screen not seen).
    public static var chosen: AppLanguage? {
        UserDefaults.standard.string(forKey: chosenKey).flatMap(AppLanguage.init(rawValue:))
    }

    /// The language the app shows right now: the chosen one, else the best match for the device.
    public static var current: AppLanguage { chosen ?? matching() }

    /// The device's language list with the app's language first: for `Accept-Language` and the
    /// device record, so server-made text (pushes, emails, web pages) matches the app.
    public static var preferredLanguages: [String] {
        let system = Locale.preferredLanguages.filter { Locale(identifier: $0).language.languageCode?.identifier != current.rawValue }
        return [current.rawValue] + system
    }

    /// `uz_UZ`-style identifier: the app's language with the device's region.
    public static var localeIdentifier: String {
        guard let chosen else { return Locale.current.identifier }
        guard let region = Locale.current.region?.identifier else { return chosen.rawValue }
        return "\(chosen.rawValue)_\(region)"
    }

    /// Makes `language` the app's language right away and on every later launch.
    ///
    /// Right away: `Bundle.main` answers string lookups from that language's `.lproj` (every module
    /// resolves its strings from the main bundle's catalog), and the root view re-renders with
    /// `.environment(\.locale, language.locale)`. Later launches: `AppleLanguages` in the app's own
    /// defaults, which is also what iOS Settings › Nameshake › Language reads and writes.
    public static func choose(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: chosenKey)
        UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        installBundleOverride(for: language)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    /// Posted after `choose(_:)`: the app root rebuilds every screen in the new language.
    public static let didChangeNotification = Notification.Name("AppLanguage.didChange")

    /// Call once at launch, before the first view: applies a language picked in an earlier run.
    /// A language changed in iOS Settings since then wins (iOS rewrote `AppleLanguages`).
    public static func applySavedChoice() {
        guard chosen != nil else { return }
        let fromSettings = (UserDefaults.standard.array(forKey: "AppleLanguages") as? [String]).map(matching)
        if let fromSettings, fromSettings != chosen {
            UserDefaults.standard.set(fromSettings.rawValue, forKey: chosenKey)
        }
        installBundleOverride(for: current)
    }

    /// Forgets the choice (tests).
    public static func resetChoice() {
        UserDefaults.standard.removeObject(forKey: chosenKey)
        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        LocalizedBundle.override = nil
    }

    private static let chosenKey = "pref.language"

    private static func installBundleOverride(for language: AppLanguage) {
        guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return }
        LocalizedBundle.override = bundle
        LocalizedBundle.install()
    }
}

public extension Bundle {
    /// Where app strings are read from: the language picked in the app, else `Bundle.main`.
    ///
    /// Every `String(localized:)` / `AttributedString(localized:)` passes `bundle: .appStrings`. Foundation
    /// resolves those through CoreFoundation, which fixes the main bundle's language at launch, so
    /// without the explicit bundle they would stay in the old language until the next launch.
    /// (`Text` keys go through `-[NSBundle localizedStringForKey:…]`, which `LocalizedBundle` redirects.)
    static var appStrings: Bundle { LocalizedBundle.override ?? .main }
}

/// `Bundle.main`'s class while a language is chosen in the app: string lookups go to that language.
private final class LocalizedBundle: Bundle, @unchecked Sendable {
    nonisolated(unsafe) static var override: Bundle?
    nonisolated(unsafe) private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        object_setClass(Bundle.main, LocalizedBundle.self)
    }

    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let override = Self.override {
            return override.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }

}

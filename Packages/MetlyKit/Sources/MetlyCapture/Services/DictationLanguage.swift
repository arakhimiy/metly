import Foundation

/// The language voice notes are recognized in. Apple's on-device speech models cover Russian and English
/// but not Uzbek (no SFSpeechRecognizer / SpeechTranscriber / DictationTranscriber locale), so those are
/// the two choices. The exact locale is always passed to the recognizer — never `Locale.current`, which
/// is e.g. `en_UZ` for many Uzbek users and turned Russian speech into English nonsense.
nonisolated public enum DictationLanguage: String, CaseIterable, Identifiable, Sendable {
    case russian = "ru-RU"
    case english = "en-US"

    public var id: String { rawValue }

    /// The locale handed to SpeechAnalyzer / SFSpeechRecognizer.
    public var locale: Locale { Locale(identifier: rawValue) }

    /// The language's own name, as iOS lists keyboards and dictation languages ("Русский", "English").
    public var nativeName: String {
        switch self {
        case .russian: "Русский"
        case .english: "English"
        }
    }

    /// Short code for compact UI ("RU", "EN").
    public var shortName: String {
        switch self {
        case .russian: "RU"
        case .english: "EN"
        }
    }

    /// Russian when the user's preferred languages include Russian or Uzbek (Uzbek speakers in Uzbekistan
    /// almost always speak Russian too, and Uzbek isn't available), otherwise English.
    public static func defaultLanguage(preferredLanguages: [String] = Locale.preferredLanguages) -> DictationLanguage {
        let codes = preferredLanguages.map { Locale(identifier: $0).language.languageCode?.identifier.lowercased() }
        return codes.contains { $0 == "ru" || $0 == "uz" } ? .russian : .english
    }

    /// Whether the app's UI is shown in Uzbek (the language menu then explains Uzbek isn't available yet).
    public static func isUzbekAppLanguage(
        preferredLocalizations: [String] = Bundle.main.preferredLocalizations) -> Bool {
        guard let first = preferredLocalizations.first else { return false }
        return Locale(identifier: first).language.languageCode?.identifier.lowercased() == "uz"
    }
}

/// Remembers the chosen dictation language across launches (device-local, not synced).
nonisolated public struct DictationLanguageStore: Sendable {
    static let key = "pref.dictationLanguage"

    private let suiteName: String?

    /// `suiteName` nil = standard defaults; tests pass their own suite.
    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    /// The saved choice, or the default for the user's languages when nothing (valid) was saved.
    public func load(preferredLanguages: [String] = Locale.preferredLanguages) -> DictationLanguage {
        defaults.string(forKey: Self.key).flatMap(DictationLanguage.init(rawValue:))
            ?? .defaultLanguage(preferredLanguages: preferredLanguages)
    }

    public func save(_ language: DictationLanguage) {
        defaults.set(language.rawValue, forKey: Self.key)
    }
}

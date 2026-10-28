import Foundation

/// Why voice notes can't start in the chosen language. Never answered by silently switching to another
/// language: the form explains what to do instead.
nonisolated public enum DictationUnavailability: Equatable, Sendable {
    /// iOS 18–25 (or no SpeechAnalyzer model): iOS has the language but not its on-device model. The user adds
    /// it under Settings › General › Keyboard › Dictation Languages.
    case needsDictationLanguage(DictationLanguage)
    /// iOS 26+: the system couldn't download the on-device speech model (offline, no space). Retry.
    case modelDownloadFailed(DictationLanguage)
    /// Speech recognition for the language is momentarily unavailable (the recognizer reports so). Retry.
    case temporarilyUnavailable(DictationLanguage)
    /// This iPhone can't recognize the language on-device at all.
    case notSupported(DictationLanguage)

    public var language: DictationLanguage {
        switch self {
        case .needsDictationLanguage(let language), .modelDownloadFailed(let language),
             .temporarilyUnavailable(let language), .notSupported(let language):
            language
        }
    }

    /// Whether trying again right away can help (offers "Try Again").
    public var isRetryable: Bool {
        switch self {
        case .modelDownloadFailed, .temporarilyUnavailable: true
        case .needsDictationLanguage, .notSupported: false
        }
    }
}

/// What preparing a dictation session for a language produced.
nonisolated enum DictationSetup: Sendable {
    case ready(any DictationSession)
    case unavailable(DictationUnavailability)
}

/// SFSpeechRecognizer's on-device readiness for one locale (iOS 18–25 path), from its three flags.
nonisolated enum OnDeviceRecognizerSupport: Equatable, Sendable {
    case ready
    /// The recognizer exists but only works through Apple's servers — the on-device model isn't installed.
    case needsDictationLanguage
    case temporarilyUnavailable
    case unsupported

    /// - Parameters:
    ///   - recognizerExists: `SFSpeechRecognizer(locale:)` returned a recognizer.
    ///   - isAvailable: `recognizer.isAvailable`.
    ///   - supportsOnDevice: `recognizer.supportsOnDeviceRecognition`.
    static func classify(recognizerExists: Bool, isAvailable: Bool, supportsOnDevice: Bool) -> OnDeviceRecognizerSupport {
        guard recognizerExists else { return .unsupported }
        // On-device support is the deciding flag: without it we never record (PLAN Q17, on-device only).
        guard supportsOnDevice else { return .needsDictationLanguage }
        return isAvailable ? .ready : .temporarilyUnavailable
    }

    func unavailability(for language: DictationLanguage) -> DictationUnavailability? {
        switch self {
        case .ready: nil
        case .needsDictationLanguage: .needsDictationLanguage(language)
        case .temporarilyUnavailable: .temporarilyUnavailable(language)
        case .unsupported: .notSupported(language)
        }
    }
}

nonisolated enum DictationLocale {
    /// Whether a locale the speech APIs offered as "equivalent" is really the requested language — so a
    /// Russian request can never end up on an English model.
    static func isSameLanguage(_ offered: Locale, as requested: Locale) -> Bool {
        guard let offeredCode = offered.language.languageCode, let requestedCode = requested.language.languageCode else {
            return false
        }
        return offeredCode == requestedCode
    }

    /// Same locale for AssetInventory reservations ("ru_RU" and "ru-RU" match).
    static func isSameLocale(_ lhs: Locale, _ rhs: Locale) -> Bool {
        lhs.identifier(.bcp47).caseInsensitiveCompare(rhs.identifier(.bcp47)) == .orderedSame
    }
}

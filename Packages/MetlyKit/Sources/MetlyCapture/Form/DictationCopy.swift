import Foundation

/// User-facing dictation texts. Whole sentences per language (no "%@ dictation" fragments), so Russian and
/// Uzbek translations can decline the language name properly.
enum DictationCopy {
    static func title(for reason: DictationUnavailability) -> String {
        switch reason {
        case .needsDictationLanguage(.russian): String(localized: "Russian Dictation Isn’t Set Up")
        case .needsDictationLanguage(.english): String(localized: "English Dictation Isn’t Set Up")
        case .modelDownloadFailed: String(localized: "Download Didn’t Finish")
        case .temporarilyUnavailable, .notSupported: String(localized: "Voice Notes Unavailable")
        }
    }

    static func message(for reason: DictationUnavailability) -> String {
        switch reason {
        case .needsDictationLanguage(.russian):
            String(localized: "Voice notes are recognized on this iPhone, so iOS needs its Russian dictation model. Go to Settings › General › Keyboard › Dictation Languages and turn on Russian (add the Russian keyboard first if it isn’t listed), then try again.")
        case .needsDictationLanguage(.english):
            String(localized: "Voice notes are recognized on this iPhone, so iOS needs its English dictation model. Go to Settings › General › Keyboard › Dictation Languages and turn on English (add an English keyboard first if it isn’t listed), then try again.")
        case .modelDownloadFailed(.russian):
            String(localized: "iOS couldn’t download the Russian speech model for voice notes. Check your internet connection and free storage, then try again.")
        case .modelDownloadFailed(.english):
            String(localized: "iOS couldn’t download the English speech model for voice notes. Check your internet connection and free storage, then try again.")
        case .temporarilyUnavailable(.russian):
            String(localized: "Russian dictation isn’t available right now. Try again in a moment.")
        case .temporarilyUnavailable(.english):
            String(localized: "English dictation isn’t available right now. Try again in a moment.")
        case .notSupported(.russian):
            String(localized: "This iPhone can’t recognize Russian speech on-device. You can still type your note.")
        case .notSupported(.english):
            String(localized: "This iPhone can’t recognize English speech on-device. You can still type your note.")
        }
    }

    /// Status line while iOS downloads the on-device model.
    static func downloading(_ language: DictationLanguage) -> String {
        switch language {
        case .russian: String(localized: "Downloading the Russian speech model…")
        case .english: String(localized: "Downloading the English speech model…")
        }
    }

    static let uzbekUnavailable = String(localized: "Uzbek voice notes aren’t available yet.")
}

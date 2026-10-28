import Foundation
import Testing
@testable import MetlyCapture

/// A store on its own empty defaults suite, so tests never see each other's (or the simulator's) choice.
func freshStore() -> DictationLanguageStore {
    let suite = "metly.tests.dictation.\(UUID().uuidString)"
    UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    return DictationLanguageStore(suiteName: suite)
}

@MainActor
struct DictationLanguageTests {
    private let granted = VoiceNoteRecognizer.Permissions(microphone: { true }, speech: { true })

    // MARK: Default language

    @Test func russianIsTheDefaultForRussianAndUzbekSpeakers() {
        #expect(DictationLanguage.defaultLanguage(preferredLanguages: ["ru-RU"]) == .russian)
        #expect(DictationLanguage.defaultLanguage(preferredLanguages: ["uz-UZ"]) == .russian)
        #expect(DictationLanguage.defaultLanguage(preferredLanguages: ["uz-Cyrl-UZ"]) == .russian)
        #expect(DictationLanguage.defaultLanguage(preferredLanguages: ["uz-Latn"]) == .russian)
        // Regression: an English UI in Uzbekistan ("en-UZ") with Russian further down the list.
        #expect(DictationLanguage.defaultLanguage(preferredLanguages: ["en-UZ", "ru-UZ"]) == .russian)
    }

    @Test func englishIsTheDefaultOtherwise() {
        #expect(DictationLanguage.defaultLanguage(preferredLanguages: ["en-US"]) == .english)
        #expect(DictationLanguage.defaultLanguage(preferredLanguages: ["en-UZ"]) == .english)
        #expect(DictationLanguage.defaultLanguage(preferredLanguages: ["de-DE", "tr-TR"]) == .english)
        #expect(DictationLanguage.defaultLanguage(preferredLanguages: []) == .english)
    }

    @Test func uzbekAppLanguageIsDetected() {
        #expect(DictationLanguage.isUzbekAppLanguage(preferredLocalizations: ["uz"]))
        #expect(DictationLanguage.isUzbekAppLanguage(preferredLocalizations: ["uz-Cyrl", "en"]))
        #expect(!DictationLanguage.isUzbekAppLanguage(preferredLocalizations: ["ru", "uz"]))
        #expect(!DictationLanguage.isUzbekAppLanguage(preferredLocalizations: ["en"]))
        #expect(!DictationLanguage.isUzbekAppLanguage(preferredLocalizations: []))
    }

    // MARK: Locale selection

    /// Regression: `Locale.current` ("en_UZ") was passed to the recognizer, so Russian speech came out as English.
    @Test func eachLanguageUsesItsExactLocale() {
        #expect(DictationLanguage.russian.locale.identifier(.bcp47) == "ru-RU")
        #expect(DictationLanguage.russian.locale.language.languageCode == .russian)
        #expect(DictationLanguage.english.locale.identifier(.bcp47) == "en-US")
        #expect(DictationLanguage.english.locale.language.languageCode == .english)
    }

    @Test func anOfferedLocaleMustBeTheRequestedLanguage() {
        let russian = DictationLanguage.russian.locale
        #expect(DictationLocale.isSameLanguage(Locale(identifier: "ru_RU"), as: russian))
        #expect(DictationLocale.isSameLanguage(Locale(identifier: "ru"), as: russian))
        #expect(!DictationLocale.isSameLanguage(Locale(identifier: "en_US"), as: russian))
        #expect(!DictationLocale.isSameLanguage(Locale(identifier: "uk_UA"), as: russian))
        #expect(DictationLocale.isSameLocale(Locale(identifier: "ru_RU"), russian))
        #expect(!DictationLocale.isSameLocale(Locale(identifier: "en_US"), russian))
    }

    // MARK: Remembered choice

    @Test func theStoreRemembersTheChoice() {
        let store = freshStore()
        #expect(store.load(preferredLanguages: ["uz-UZ"]) == .russian)
        store.save(.english)
        #expect(store.load(preferredLanguages: ["uz-UZ"]) == .english)
        store.save(.russian)
        #expect(store.load(preferredLanguages: ["en-US"]) == .russian)
    }

    @Test func anUnknownSavedValueFallsBackToTheDefault() {
        let suite = "metly.tests.dictation.\(UUID().uuidString)"
        UserDefaults(suiteName: suite)?.set("uz-UZ", forKey: DictationLanguageStore.key)
        let store = DictationLanguageStore(suiteName: suite)
        #expect(store.load(preferredLanguages: ["en-US"]) == .english)
    }

    @Test func theRecognizerStartsWithTheRememberedLanguageAndSavesChanges() {
        let store = freshStore()
        let first = VoiceNoteRecognizer(store: store, preferredLanguages: ["uz-UZ"], permissions: granted) { _, _ in
            .unavailable(.notSupported(.russian))
        }
        #expect(first.language == .russian)
        first.language = .english
        let second = VoiceNoteRecognizer(store: store, preferredLanguages: ["uz-UZ"], permissions: granted) { _, _ in
            .unavailable(.notSupported(.english))
        }
        #expect(second.language == .english)
    }

    @Test func theChosenLanguageIsWhatTheSessionIsPreparedFor() async {
        var requested: [DictationLanguage] = []
        let session = FakeDictationSession()
        let recognizer = VoiceNoteRecognizer(store: freshStore(), preferredLanguages: ["en-US"],
                                             permissions: granted) { language, _ in
            requested.append(language)
            return .ready(session)
        }
        recognizer.language = .russian
        await recognizer.startAndWait()
        #expect(requested == [.russian])
        #expect(recognizer.state == .listening)
        recognizer.cancel()
    }

    // MARK: Unsupported on-device

    @Test func onDeviceSupportIsClassifiedFromTheRecognizerFlags() {
        #expect(OnDeviceRecognizerSupport.classify(recognizerExists: true, isAvailable: true, supportsOnDevice: true) == .ready)
        // Russian exists server-side, but the on-device model isn't installed: never record then.
        #expect(OnDeviceRecognizerSupport.classify(recognizerExists: true, isAvailable: true, supportsOnDevice: false)
                == .needsDictationLanguage)
        #expect(OnDeviceRecognizerSupport.classify(recognizerExists: true, isAvailable: false, supportsOnDevice: false)
                == .needsDictationLanguage)
        #expect(OnDeviceRecognizerSupport.classify(recognizerExists: true, isAvailable: false, supportsOnDevice: true)
                == .temporarilyUnavailable)
        #expect(OnDeviceRecognizerSupport.classify(recognizerExists: false, isAvailable: false, supportsOnDevice: false)
                == .unsupported)
        #expect(OnDeviceRecognizerSupport.needsDictationLanguage.unavailability(for: .russian) == .needsDictationLanguage(.russian))
        #expect(OnDeviceRecognizerSupport.ready.unavailability(for: .russian) == nil)
    }

    /// Regression: without a Russian on-device model the recognizer quietly listened in English.
    @Test func missingRussianModelIsReportedWithoutFallingBackToEnglish() async {
        var requested: [DictationLanguage] = []
        let recognizer = VoiceNoteRecognizer(store: freshStore(), preferredLanguages: ["ru-RU"],
                                             permissions: granted) { language, _ in
            requested.append(language)
            return .unavailable(.needsDictationLanguage(language))
        }
        await recognizer.startAndWait()
        #expect(requested == [.russian])
        #expect(recognizer.state == .unavailable(.needsDictationLanguage(.russian)))
        #expect(recognizer.language == .russian)

        let problem = DictationProblem(.needsDictationLanguage(.russian))
        #expect(problem.message.contains("Settings › General › Keyboard › Dictation Languages"))
        #expect(problem.message.contains("Russian"))
        #expect(!problem.canRetry)
    }

    @Test func switchingLanguageClearsTheUnavailableState() async {
        let recognizer = VoiceNoteRecognizer(store: freshStore(), preferredLanguages: ["ru-RU"],
                                             permissions: granted) { language, _ in
            .unavailable(.needsDictationLanguage(language))
        }
        await recognizer.startAndWait()
        #expect(recognizer.state == .unavailable(.needsDictationLanguage(.russian)))
        recognizer.language = .english
        #expect(recognizer.state == .idle)
    }

    // MARK: Model download (iOS 26+)

    @Test func modelDownloadProgressIsShownThenListeningStarts() async throws {
        let gate = PendingPrompt()
        let session = FakeDictationSession()
        let recognizer = VoiceNoteRecognizer(store: freshStore(), permissions: granted) { _, progress in
            await progress(0.4)
            _ = await gate.ask()
            await progress(1.7)   // clamped
            return .ready(session)
        }
        recognizer.start()
        try await waitFor { gate.isShowing }
        #expect(recognizer.state == .downloadingModel(0.4))
        #expect(recognizer.isBusy)
        gate.answer(true)
        try await waitFor { recognizer.state == .listening }
        #expect(session.started)
        recognizer.cancel()
    }

    @Test func stoppingDuringTheDownloadNeverStartsTheMicrophone() async throws {
        let gate = PendingPrompt()
        let session = FakeDictationSession()
        let recognizer = VoiceNoteRecognizer(store: freshStore(), permissions: granted) { _, progress in
            await progress(nil)
            _ = await gate.ask()
            return .ready(session)
        }
        recognizer.start()
        try await waitFor { gate.isShowing }
        #expect(recognizer.state == .downloadingModel(nil))
        recognizer.stop()
        #expect(recognizer.state == .idle)
        gate.answer(true)
        try await Task.sleep(for: .milliseconds(100))
        #expect(recognizer.state == .idle)
        #expect(!session.started)
        #expect(session.cancelled)
    }

    @Test func aFailedDownloadOffersRetryWhichCanSucceed() async throws {
        var attempts = 0
        let session = FakeDictationSession()
        let recognizer = VoiceNoteRecognizer(store: freshStore(), preferredLanguages: ["ru-RU"],
                                             permissions: granted) { language, _ in
            attempts += 1
            return attempts == 1 ? .unavailable(.modelDownloadFailed(language)) : .ready(session)
        }
        await recognizer.startAndWait()
        #expect(recognizer.state == .unavailable(.modelDownloadFailed(.russian)))
        #expect(DictationProblem(.modelDownloadFailed(.russian)).canRetry)

        recognizer.retry()
        try await waitFor { recognizer.state == .listening }
        #expect(attempts == 2)
        recognizer.cancel()
    }

    @Test func everyUnavailabilityHasCopy() {
        for language in DictationLanguage.allCases {
            let reasons: [DictationUnavailability] = [.needsDictationLanguage(language), .modelDownloadFailed(language),
                                                      .temporarilyUnavailable(language), .notSupported(language)]
            for reason in reasons {
                #expect(!DictationCopy.title(for: reason).isEmpty)
                #expect(!DictationCopy.message(for: reason).isEmpty)
                #expect(reason.language == language)
            }
            #expect(!DictationCopy.downloading(language).isEmpty)
        }
    }
}

@MainActor
func waitFor(timeout: Duration = .seconds(2), _ condition: @MainActor () -> Bool) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else {
            Issue.record("Timed out waiting")
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}

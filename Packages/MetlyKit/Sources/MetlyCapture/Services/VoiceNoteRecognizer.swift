import AVFAudio
import Foundation
import Observation
import Speech

/// Voice dictation for private notes, on-device only (PLAN Q17), in the language picked next to the mic
/// (`DictationLanguage`: Russian or English, remembered across launches; Apple has no Uzbek model):
/// iOS 26+ `SpeechAnalyzer` (long-form; the system downloads the model on first use, reported as
/// `.downloadingModel`), iOS 18–25 `SFSpeechRecognizer` restarted every time a task ends so long notes keep
/// going. Without an on-device model for the language it reports why (`.unavailable`) — it never quietly
/// listens in another language. Asks for Microphone, then Speech Recognition, the first time `start()` is
/// called (in context). `transcript` updates live while listening; audio isn't stored.
///
/// The microphone never outlives the form: the start sequence holds the recognizer weakly, and dropping
/// the recognizer (the form went away) cancels the session — engine stopped, tap removed.
@Observable
public final class VoiceNoteRecognizer {
    public enum Permission: Sendable { case microphone, speech }

    public enum State: Equatable, Sendable {
        case idle
        case preparing
        /// iOS 26+: the system is downloading the language's on-device model (0…1, nil while unknown).
        case downloadingModel(Double?)
        case listening
        case denied(Permission)
        /// No on-device recognition for the chosen language right now, and what to do about it.
        case unavailable(DictationUnavailability)
        case failed(String)
    }

    /// Permission prompts (injectable for tests).
    struct Permissions {
        var microphone: @MainActor () async -> Bool
        var speech: @MainActor () async -> Bool

        static let system = Permissions(
            microphone: { await AVAudioApplication.requestRecordPermission() },
            speech: { await VoiceNoteRecognizer.speechAuthorization() == .authorized })
    }

    /// Reports model download progress (0…1, nil = unknown) while a session is being prepared.
    typealias ProgressHandler = @Sendable (Double?) async -> Void
    /// Prepares a session for exactly this language (tests inject fakes).
    typealias SessionFactory = @MainActor (DictationLanguage, @escaping ProgressHandler) async -> DictationSetup

    public private(set) var state: State = .idle
    /// Text recognized in the current (or last) run.
    public private(set) var transcript = ""
    /// The language the next run listens in. Remembered across launches; change it only while idle.
    public var language: DictationLanguage {
        didSet {
            guard language != oldValue else { return }
            store.save(language)
            if case .unavailable = state { state = .idle }
        }
    }

    /// Names and words likely to be said (people, companies, the event); see `DictationVocabulary`.
    @ObservationIgnored public var vocabulary: [String] = []
    @ObservationIgnored private let store: DictationLanguageStore
    @ObservationIgnored private let permissions: Permissions
    @ObservationIgnored private let makeSession: SessionFactory
    /// Nonisolated so `deinit` can stop the microphone when the form goes away.
    @ObservationIgnored nonisolated(unsafe) private var session: (any DictationSession)?
    @ObservationIgnored nonisolated(unsafe) private var startTask: Task<Void, Never>?
    @ObservationIgnored private var listenTask: Task<Void, Never>?

    /// Uses the remembered language (Russian by default for Russian / Uzbek speakers, else English).
    public convenience init() {
        self.init(store: DictationLanguageStore(), permissions: .system) { language, progress in
            await VoiceNoteRecognizer.systemSetup(for: language, progress: progress)
        }
    }

    init(store: DictationLanguageStore, preferredLanguages: [String] = Locale.preferredLanguages,
         permissions: Permissions, makeSession: @escaping SessionFactory) {
        self.store = store
        self.language = store.load(preferredLanguages: preferredLanguages)
        self.permissions = permissions
        self.makeSession = makeSession
    }

    deinit {
        startTask?.cancel()
        session?.cancel()
    }

    public var isListening: Bool { state == .listening }

    /// Preparing, downloading the model or listening — the mic button then stops.
    public var isBusy: Bool {
        switch state {
        case .preparing, .downloadingModel, .listening: true
        case .idle, .denied, .unavailable, .failed: false
        }
    }

    public func toggle() {
        if isBusy {
            stop()
        } else {
            start()
        }
    }

    /// Asks for permissions if needed, prepares the language's on-device model (the system downloads it the
    /// first time on iOS 26+), then starts listening. Returns right away; watch `state`.
    public func start() {
        guard !isBusy else { return }
        state = .preparing
        transcript = ""
        let language = language
        let permissions = permissions
        let makeSession = makeSession
        let vocabulary = vocabulary
        let progress: ProgressHandler = { [weak self] fraction in
            await self?.modelDownloadProgressed(fraction)
        }
        // Weak: a form dismissed during a permission prompt or model download must not start the microphone.
        startTask = Task { [weak self] in
            guard await permissions.microphone() else {
                self?.preparationEnded(.denied(.microphone))
                return
            }
            guard self?.isPreparing == true else { return }
            guard await permissions.speech() else {
                self?.preparationEnded(.denied(.speech))
                return
            }
            guard self?.isPreparing == true else { return }
            let session: any DictationSession
            switch await makeSession(language, progress) {
            case .ready(let ready):
                session = ready
            case .unavailable(let reason):
                self?.preparationEnded(.unavailable(reason))
                return
            }
            guard !Task.isCancelled, self?.adopt(session) == true else {
                session.cancel()
                return
            }
            let events: AsyncStream<DictationEvent>
            do {
                events = try await session.start(vocabulary: vocabulary)
            } catch {
                session.cancel()
                self?.sessionFailedToStart(session)
                return
            }
            guard !Task.isCancelled, self?.listen(to: events, from: session) == true else {
                session.cancel()
                return
            }
        }
    }

    /// Waits for the start sequence (tests).
    func startAndWait() async {
        start()
        await startTask?.value
    }

    /// Stops listening and keeps what was recognized so far. While preparing (a permission prompt, the model
    /// download) it just stops waiting — the system keeps downloading the model for next time.
    public func stop() {
        if isPreparing {
            startTask?.cancel()
            state = .idle
        }
        session?.finish()
    }

    /// Stops and discards the session (e.g. when the form disappears).
    public func cancel() {
        startTask?.cancel()
        startTask = nil
        listenTask?.cancel()
        listenTask = nil
        session?.cancel()
        session = nil
        if isBusy { state = .idle }
    }

    /// Clears a denied / unavailable / failed state after the UI showed it.
    public func acknowledge() {
        switch state {
        case .denied, .unavailable, .failed: state = .idle
        default: break
        }
    }

    /// "Try Again" after a failed model download or a momentary outage.
    public func retry() {
        acknowledge()
        start()
    }

    // MARK: Private

    /// Before listening: waiting on permissions or the model.
    private var isPreparing: Bool {
        switch state {
        case .preparing, .downloadingModel: true
        default: false
        }
    }

    private func modelDownloadProgressed(_ fraction: Double?) {
        guard isPreparing else { return }
        state = .downloadingModel(fraction.map { min(max($0, 0), 1) })
    }

    private func preparationEnded(_ newState: State) {
        guard isPreparing else { return }
        state = newState
    }

    /// Keeps `newSession` if dictation is still wanted (not stopped while preparing).
    private func adopt(_ newSession: any DictationSession) -> Bool {
        guard isPreparing else { return false }
        session = newSession
        return true
    }

    private func sessionFailedToStart(_ failed: any DictationSession) {
        if session === failed { session = nil }
        preparationEnded(.failed(String(localized: "The microphone couldn’t start. Try again.", bundle: .appStrings)))
    }

    private func listen(to events: AsyncStream<DictationEvent>, from started: any DictationSession) -> Bool {
        guard isPreparing, session === started else {
            if session === started { session = nil }
            return false
        }
        state = .listening
        listenTask = Task { [weak self] in
            for await event in events {
                self?.handle(event)
            }
            self?.didFinish()
        }
        return true
    }

    private func handle(_ event: DictationEvent) {
        switch event {
        case .partial(let text), .final(let text):
            transcript = text
        case .failed(let message):
            state = .failed(message)
        }
    }

    private func didFinish() {
        session = nil
        listenTask = nil
        if isBusy { state = .idle }
    }

    /// SpeechAnalyzer on iOS 26+ (downloading the model if needed), otherwise SFSpeechRecognizer — both in
    /// exactly `language`'s locale and on-device only.
    static func systemSetup(for language: DictationLanguage, progress: @escaping ProgressHandler) async -> DictationSetup {
        let locale = language.locale
        if #available(iOS 26, *) {
            switch await AnalyzerDictationSession.prepare(locale: locale, progress: progress) {
            case .ready(let session): return .ready(session)
            case .downloadFailed: return .unavailable(.modelDownloadFailed(language))
            case .unsupported: break   // older devices: SFSpeechRecognizer may still have an on-device model
            }
        }
        let (session, support) = SpeechSession.make(locale: locale)
        if let session { return .ready(session) }
        return .unavailable(support.unavailability(for: language) ?? .notSupported(language))
    }

    static func speechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in
            requestSpeechAuthorization(continuation)
        }
    }

    /// Nonisolated so the system callback (background queue) isn't treated as main-actor code.
    nonisolated private static func requestSpeechAuthorization(
        _ continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) {
        SFSpeechRecognizer.requestAuthorization { status in
            continuation.resume(returning: status)
        }
    }
}

import AVFAudio
import Foundation
import Observation
import Speech

/// Voice dictation for private notes, on-device only (PLAN Q17):
/// iOS 26+ `SpeechAnalyzer` (long-form), iOS 18–25 `SFSpeechRecognizer` restarted every time a task ends
/// so long notes keep going. Asks for Microphone, then Speech Recognition, the first time `start()` is
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
        case listening
        case denied(Permission)
        /// On-device recognition isn't available for this language / device right now.
        case unavailable
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

    typealias SessionFactory = @MainActor (Locale) async -> (any DictationSession)?

    public private(set) var state: State = .idle
    /// Text recognized in the current (or last) run.
    public private(set) var transcript = ""

    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private let permissions: Permissions
    @ObservationIgnored private let makeSession: SessionFactory
    /// Nonisolated so `deinit` can stop the microphone when the form goes away.
    @ObservationIgnored nonisolated(unsafe) private var session: (any DictationSession)?
    @ObservationIgnored nonisolated(unsafe) private var startTask: Task<Void, Never>?
    @ObservationIgnored private var listenTask: Task<Void, Never>?

    public convenience init(locale: Locale = .current) {
        self.init(locale: locale, permissions: .system) { await VoiceNoteRecognizer.systemSession(locale: $0) }
    }

    init(locale: Locale, permissions: Permissions, makeSession: @escaping SessionFactory) {
        self.locale = locale
        self.permissions = permissions
        self.makeSession = makeSession
    }

    deinit {
        startTask?.cancel()
        session?.cancel()
    }

    public var isListening: Bool { state == .listening }
    public var isBusy: Bool { state == .listening || state == .preparing }

    public func toggle() {
        if isBusy {
            stop()
        } else {
            start()
        }
    }

    /// Asks for permissions if needed, then starts listening. Returns right away; watch `state`.
    public func start() {
        guard !isBusy else { return }
        state = .preparing
        transcript = ""
        let locale = locale
        let permissions = permissions
        let makeSession = makeSession
        // Weak: a form dismissed during a permission prompt or model download must not start the microphone.
        startTask = Task { [weak self] in
            guard await permissions.microphone() else {
                self?.preparationEnded(.denied(.microphone))
                return
            }
            guard self?.state == .preparing else { return }
            guard await permissions.speech() else {
                self?.preparationEnded(.denied(.speech))
                return
            }
            guard self?.state == .preparing else { return }
            guard let session = await makeSession(locale) else {
                self?.preparationEnded(.unavailable)
                return
            }
            guard !Task.isCancelled, self?.adopt(session) == true else {
                session.cancel()
                return
            }
            let events: AsyncStream<DictationEvent>
            do {
                events = try await session.start()
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

    /// Stops listening and keeps what was recognized so far.
    public func stop() {
        if state == .preparing {
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

    /// Clears a denied / failed state after the UI showed it.
    public func acknowledge() {
        switch state {
        case .denied, .unavailable, .failed: state = .idle
        default: break
        }
    }

    // MARK: Private

    private func preparationEnded(_ newState: State) {
        guard state == .preparing else { return }
        state = newState
    }

    /// Keeps `newSession` if dictation is still wanted (not stopped while preparing).
    private func adopt(_ newSession: any DictationSession) -> Bool {
        guard state == .preparing else { return false }
        session = newSession
        return true
    }

    private func sessionFailedToStart(_ failed: any DictationSession) {
        if session === failed { session = nil }
        preparationEnded(.unavailable)
    }

    private func listen(to events: AsyncStream<DictationEvent>, from started: any DictationSession) -> Bool {
        guard state == .preparing, session === started else {
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

    /// SpeechAnalyzer on iOS 26+ where a model exists for the language, otherwise SFSpeechRecognizer.
    static func systemSession(locale: Locale) async -> (any DictationSession)? {
        if #available(iOS 26, *), let session = await AnalyzerDictationSession.make(locale: locale) {
            return session
        }
        return SpeechSession(locale: locale)
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

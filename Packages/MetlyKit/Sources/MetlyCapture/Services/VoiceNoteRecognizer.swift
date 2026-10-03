import AVFAudio
import Foundation
import Observation
import Speech

/// Voice dictation for private notes (on-device `SFSpeechRecognizer` + `AVAudioEngine`).
/// Asks for Microphone, then Speech Recognition, the first time `start()` is called (in context).
/// `transcript` updates live while listening; audio isn't stored.
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

    public private(set) var state: State = .idle
    /// Text recognized in the current (or last) run.
    public private(set) var transcript = ""

    @ObservationIgnored private let locale: Locale
    /// Nonisolated so `deinit` can stop the microphone when the form goes away.
    @ObservationIgnored nonisolated(unsafe) private var session: SpeechSession?
    @ObservationIgnored private var listenTask: Task<Void, Never>?

    public init(locale: Locale = .current) {
        self.locale = locale
    }

    deinit {
        session?.cancel()
    }

    public var isListening: Bool { state == .listening }
    public var isBusy: Bool { state == .listening || state == .preparing }

    public func toggle() async {
        if isBusy {
            stop()
        } else {
            await start()
        }
    }

    public func start() async {
        guard !isBusy else { return }
        state = .preparing
        transcript = ""

        guard await AVAudioApplication.requestRecordPermission() else {
            state = .denied(.microphone)
            return
        }
        guard await Self.speechAuthorization() == .authorized else {
            state = .denied(.speech)
            return
        }
        guard state == .preparing else { return }  // stopped while asking
        guard let session = SpeechSession(locale: locale) else {
            state = .unavailable
            return
        }

        do {
            let events = try session.start()
            self.session = session
            state = .listening
            listenTask = Task { [weak self] in
                for await event in events {
                    self?.handle(event)
                }
                self?.didFinish()
            }
        } catch {
            state = .unavailable
        }
    }

    /// Stops listening and keeps what was recognized so far.
    public func stop() {
        if state == .preparing { state = .idle }
        session?.finish()
    }

    /// Stops and discards the session (e.g. when the form disappears).
    public func cancel() {
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

    private func handle(_ event: SpeechSession.Event) {
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

    private static func speechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
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

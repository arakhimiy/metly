import AVFAudio
import Foundation

/// What one dictation run reports.
nonisolated enum DictationEvent: Equatable, Sendable {
    /// Everything recognized so far (finalized text + the recognizer's current guess).
    case partial(String)
    /// The run ended normally; the complete transcript.
    case final(String)
    case failed(String)
}

/// One microphone → text run: `AnalyzerDictationSession` (SpeechAnalyzer, iOS 26+) or `SpeechSession`
/// (SFSpeechRecognizer, iOS 18+ fallback). `finish()` and `cancel()` always stop the audio engine,
/// remove the input tap and deactivate the audio session, so the microphone is off afterwards.
nonisolated protocol DictationSession: AnyObject, Sendable {
    /// Starts the microphone and recognition. Events arrive until the stream finishes.
    /// - Parameter vocabulary: names and words likely to be said (people, companies, the event) —
    ///   the recognizer favours them over similar-sounding words.
    func start(vocabulary: [String]) async throws -> AsyncStream<DictationEvent>
    /// Stops listening; the final transcript follows, then the stream finishes.
    func finish()
    /// Stops immediately and finishes the stream without a final result.
    func cancel()
}

nonisolated enum DictationSessionError: Error {
    case noMicrophoneInput
    /// `finish()` / `cancel()` arrived while the session was still starting.
    case stoppedWhileStarting
}

/// The live transcript: finalized segments plus the recognizer's current (volatile) guess.
///
/// - SpeechAnalyzer: volatile results replace each other until a final result commits that range.
/// - SFSpeechRecognizer: every task reports its whole text so far; when a task ends (≈1 minute limit,
///   a long pause) its text is committed and the next task's text is appended after it.
nonisolated struct TranscriptAccumulator: Equatable, Sendable {
    private(set) var committed = ""
    private(set) var volatile = ""

    init() {}

    var text: String { Self.join(committed, volatile) }

    /// The recognizer's current guess for the part in progress (replaces the previous guess).
    mutating func setVolatile(_ text: String) {
        volatile = Self.clean(text)
    }

    /// The part in progress is final: append it and clear the guess.
    mutating func commit(_ text: String) {
        committed = Self.join(committed, text)
        volatile = ""
    }

    /// Keeps the last guess (a task ended with an error instead of a final result).
    mutating func commitVolatile() {
        commit(volatile)
    }

    static func join(_ lhs: String, _ rhs: String) -> String {
        let lhs = clean(lhs)
        let rhs = clean(rhs)
        if lhs.isEmpty { return rhs }
        if rhs.isEmpty { return lhs }
        return lhs + " " + rhs
    }

    private static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// SFSpeechRecognizer ends a task on its own (about a minute of audio, long silences, hiccups) while the
/// user is still talking. The session then starts a new task so long notes keep going; tasks that keep
/// ending right away without any text mean recognition is broken, so it gives up after a few of those.
nonisolated struct DictationRestartPolicy: Equatable, Sendable {
    enum Decision: Equatable, Sendable { case restart, stop }

    /// A task shorter than this that heard nothing counts as a failed start.
    static let quickEnd: TimeInterval = 2
    static let maxQuickEnds = 3

    private(set) var quickEnds = 0

    init() {}

    mutating func taskEnded(after duration: TimeInterval, recognizedText: Bool) -> Decision {
        if duration < Self.quickEnd && !recognizedText {
            quickEnds += 1
        } else {
            quickEnds = 0
        }
        return quickEnds >= Self.maxQuickEnds ? .stop : .restart
    }
}

/// Shared audio plumbing for both sessions.
nonisolated enum DictationAudio {
    /// Record-only session that ducks other audio; deactivated again when dictation ends.
    static func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    static func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Calls `onInterruption` when a call, Siri or another app takes the microphone.
    static func observeInterruptions(_ onInterruption: @escaping @Sendable () -> Void) -> any NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
                                               object: AVAudioSession.sharedInstance(), queue: nil) { notification in
            let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if raw.flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .began { onInterruption() }
        }
    }
}

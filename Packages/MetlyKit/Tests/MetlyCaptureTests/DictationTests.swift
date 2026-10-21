import Foundation
import Testing
@testable import MetlyCapture

/// A scripted dictation run: records how it was stopped.
final class FakeDictationSession: DictationSession, @unchecked Sendable {
    private(set) var started = false
    private(set) var finished = false
    private(set) var cancelled = false
    private var continuation: AsyncStream<DictationEvent>.Continuation?

    func start() async throws -> AsyncStream<DictationEvent> {
        started = true
        let (stream, continuation) = AsyncStream.makeStream(of: DictationEvent.self)
        self.continuation = continuation
        return stream
    }

    func send(_ event: DictationEvent) {
        continuation?.yield(event)
    }

    func finish() {
        finished = true
        continuation?.finish()
    }

    func cancel() {
        cancelled = true
        continuation?.finish()
    }
}

/// Holds a permission prompt open until the test answers it.
@MainActor
final class PendingPrompt {
    private var continuation: CheckedContinuation<Bool, Never>?
    private(set) var isShowing = false

    func ask() async -> Bool {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            isShowing = true
        }
    }

    func answer(_ granted: Bool) {
        continuation?.resume(returning: granted)
        continuation = nil
        isShowing = false
    }
}

@MainActor
struct DictationTests {
    private let granted = VoiceNoteRecognizer.Permissions(microphone: { true }, speech: { true })

    // MARK: Transcript across segments

    @Test func volatileGuessesAreReplacedAndFinalsAppended() {
        var transcript = TranscriptAccumulator()
        transcript.setVolatile("Talked")
        transcript.setVolatile("Talked about the")
        #expect(transcript.text == "Talked about the")
        transcript.commit("Talked about the deck.")
        transcript.setVolatile("Send it")
        #expect(transcript.text == "Talked about the deck. Send it")
        transcript.commit("Send it Monday.")
        #expect(transcript.text == "Talked about the deck. Send it Monday.")
        #expect(transcript.volatile.isEmpty)
    }

    /// Regression: SFSpeechRecognizer ends its task after about a minute and the note stopped there.
    /// The next task's text must continue after the previous task's text, not replace it.
    @Test func aNewRecognizerTaskContinuesTheNote() {
        var transcript = TranscriptAccumulator()
        transcript.setVolatile("First minute of the conversation")
        transcript.commit("First minute of the conversation.")   // task 1 ended on its own
        transcript.setVolatile("and the")                        // task 2 starts from scratch
        #expect(transcript.text == "First minute of the conversation. and the")
        transcript.setVolatile("And then we talked pricing")
        transcript.commitVolatile()                              // task 2 ended with an error
        #expect(transcript.text == "First minute of the conversation. And then we talked pricing")
    }

    @Test func restartsWhileTasksHearSomethingAndGivesUpOnRepeatedEmptyFailures() {
        var policy = DictationRestartPolicy()
        #expect(policy.taskEnded(after: 61, recognizedText: true) == .restart)    // the one-minute limit
        #expect(policy.taskEnded(after: 30, recognizedText: false) == .restart)   // a long pause
        #expect(policy.taskEnded(after: 0.2, recognizedText: false) == .restart)
        #expect(policy.taskEnded(after: 0.2, recognizedText: false) == .restart)
        #expect(policy.taskEnded(after: 0.2, recognizedText: false) == .stop)

        var recovering = DictationRestartPolicy()
        _ = recovering.taskEnded(after: 0.1, recognizedText: false)
        _ = recovering.taskEnded(after: 0.1, recognizedText: false)
        #expect(recovering.taskEnded(after: 5, recognizedText: true) == .restart)
        #expect(recovering.quickEnds == 0)
    }

    // MARK: Recognizer lifecycle

    @Test func transcriptFollowsTheSessionAndStopFinishesIt() async throws {
        let session = FakeDictationSession()
        let recognizer = VoiceNoteRecognizer(locale: Locale(identifier: "en-US"), permissions: granted) { _ in session }
        await recognizer.startAndWait()
        #expect(recognizer.state == .listening)
        #expect(session.started)

        session.send(.partial("Hello"))
        session.send(.partial("Hello there"))
        try await waitFor { recognizer.transcript == "Hello there" }

        recognizer.stop()
        #expect(session.finished)
        try await waitFor { recognizer.state == .idle }
        #expect(recognizer.transcript == "Hello there")
    }

    /// Dismissing the form drops the recognizer: the microphone must stop with it.
    @Test func droppingTheRecognizerStopsTheMicrophone() async throws {
        let session = FakeDictationSession()
        var recognizer: VoiceNoteRecognizer? = VoiceNoteRecognizer(locale: Locale(identifier: "en-US"),
                                                                    permissions: granted) { _ in session }
        await recognizer?.startAndWait()
        #expect(recognizer?.state == .listening)
        weak var released = recognizer
        recognizer = nil
        #expect(released == nil)
        #expect(session.cancelled)
    }

    /// Regression: the start sequence held the recognizer strongly, so a form dismissed while the
    /// permission prompt (or the model download) was up still turned the microphone on afterwards.
    @Test func dismissingDuringThePermissionPromptNeverStartsTheMicrophone() async throws {
        let prompt = PendingPrompt()
        let session = FakeDictationSession()
        var madeSession = false
        let permissions = VoiceNoteRecognizer.Permissions(microphone: { await prompt.ask() }, speech: { true })
        var recognizer: VoiceNoteRecognizer? = VoiceNoteRecognizer(locale: Locale(identifier: "en-US"),
                                                                    permissions: permissions) { _ in
            madeSession = true
            return session
        }
        recognizer?.start()
        try await waitFor { prompt.isShowing }
        weak var released = recognizer
        recognizer = nil
        #expect(released == nil)

        prompt.answer(true)
        try await Task.sleep(for: .milliseconds(100))
        #expect(!madeSession)
        #expect(!session.started)
    }

    @Test func stoppingWhilePreparingNeverListens() async throws {
        let prompt = PendingPrompt()
        let session = FakeDictationSession()
        let permissions = VoiceNoteRecognizer.Permissions(microphone: { await prompt.ask() }, speech: { true })
        let recognizer = VoiceNoteRecognizer(locale: Locale(identifier: "en-US"), permissions: permissions) { _ in session }
        recognizer.start()
        try await waitFor { prompt.isShowing }
        recognizer.stop()
        #expect(recognizer.state == .idle)
        prompt.answer(true)
        try await Task.sleep(for: .milliseconds(100))
        #expect(recognizer.state == .idle)
        #expect(!session.started)
    }

    @Test func deniedMicrophoneIsReported() async {
        let permissions = VoiceNoteRecognizer.Permissions(microphone: { false }, speech: { true })
        let recognizer = VoiceNoteRecognizer(locale: Locale(identifier: "en-US"), permissions: permissions) { _ in nil }
        await recognizer.startAndWait()
        #expect(recognizer.state == .denied(.microphone))
        recognizer.acknowledge()
        #expect(recognizer.state == .idle)
    }

    @Test func noOnDeviceModelIsUnavailable() async {
        let recognizer = VoiceNoteRecognizer(locale: Locale(identifier: "en-US"), permissions: granted) { _ in nil }
        await recognizer.startAndWait()
        #expect(recognizer.state == .unavailable)
    }

    private func waitFor(timeout: Duration = .seconds(2), _ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("Timed out waiting")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

import AVFAudio
import Foundation
import Speech

/// iOS 18–25 dictation (and the fallback where SpeechAnalyzer has no model for the language):
/// AVAudioEngine microphone tap → `SFSpeechAudioBufferRecognitionRequest`, on-device only, in exactly the
/// chosen locale. Without the language's on-device model (Settings › General › Keyboard › Dictation
/// Languages) there is no session — the form says how to add it instead of using another language.
///
/// A recognition task stops by itself after about a minute (or a long pause). While the user hasn't
/// tapped Stop, the session commits that task's text and starts the next task on the same running
/// microphone, so long notes keep going (`DictationRestartPolicy`). Audio is never written anywhere.
/// Lives off the main actor (audio tap and recognizer callbacks run on other queues); state is guarded
/// by `lock`, and stream continuations are only touched outside it.
nonisolated final class SpeechSession: DictationSession, @unchecked Sendable {
    private let recognizer: SFSpeechRecognizer
    private let engine = AVAudioEngine()
    private let lock = NSLock()

    // Guarded by `lock`.
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var taskID = 0
    private var taskStartedAt = Date.now
    private var taskHeardSomething = false
    private var transcript = TranscriptAccumulator()
    private var restarts = DictationRestartPolicy()
    private var continuation: AsyncStream<DictationEvent>.Continuation?
    private var interruptionObserver: (any NSObjectProtocol)?
    private var finishRequested = false
    private var vocabulary: [String] = []
    private var isTornDown = false

    /// A session for exactly `locale` when this iPhone recognizes it on-device (PLAN Q17: on-device only),
    /// otherwise why not. Never falls back to another language: a Russian note must not be heard as English.
    static func make(locale: Locale) -> (session: SpeechSession?, support: OnDeviceRecognizerSupport) {
        let recognizer = SFSpeechRecognizer(locale: locale)
            .flatMap { DictationLocale.isSameLanguage($0.locale, as: locale) ? $0 : nil }
        let support = OnDeviceRecognizerSupport.classify(recognizerExists: recognizer != nil,
                                                         isAvailable: recognizer?.isAvailable ?? false,
                                                         supportsOnDevice: recognizer?.supportsOnDeviceRecognition ?? false)
        guard support == .ready, let recognizer else { return (nil, support) }
        return (SpeechSession(recognizer: recognizer), support)
    }

    private init(recognizer: SFSpeechRecognizer) {
        self.recognizer = recognizer
    }

    func start(vocabulary: [String]) async throws -> AsyncStream<DictationEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: DictationEvent.self)
        let stopped: Bool = lock.withLock {
            self.continuation = continuation
            self.vocabulary = vocabulary
            return finishRequested || isTornDown
        }
        guard !stopped else {
            teardown()
            throw DictationSessionError.stoppedWhileStarting
        }
        continuation.onTermination = { [weak self] termination in
            if case .cancelled = termination { self?.cancel() }
        }

        do {
            try DictationAudio.activateSession()
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.channelCount > 0, format.sampleRate > 0 else { throw DictationSessionError.noMicrophoneInput }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.currentRequest?.append(buffer)
            }
            engine.prepare()
            try engine.start()
        } catch {
            teardown()
            throw error
        }

        let observer = DictationAudio.observeInterruptions { [weak self] in self?.finish() }
        lock.withLock { interruptionObserver = observer }
        startTask()
        return stream
    }

    /// Stops listening; the recognizer then delivers the final transcript.
    func finish() {
        let request: SFSpeechAudioBufferRecognitionRequest? = lock.withLock {
            finishRequested = true
            return self.request
        }
        stopAudio()
        request?.endAudio()
        // The recognizer normally answers within a moment; don't leave the stream open if it doesn't.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.finishWithCurrentText()
        }
    }

    /// Stops immediately without a final result.
    func cancel() {
        let task = lock.withLock { self.task }
        task?.cancel()
        teardown()
    }

    // MARK: Recognition tasks

    private var currentRequest: SFSpeechAudioBufferRecognitionRequest? {
        lock.withLock { request }
    }

    private func startTask() {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        request.contextualStrings = lock.withLock { vocabulary }

        let id: Int? = lock.withLock {
            guard !isTornDown else { return nil }
            taskID += 1
            self.request = request
            taskStartedAt = .now
            taskHeardSomething = false
            return taskID
        }
        guard let id else { return }
        let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            self?.handle(result: result, error: error, taskID: id)
        }
        lock.withLock {
            if taskID == id { self.task = task }
        }
    }

    private enum Step {
        case ignore
        case partial(String)
        case taskEnded
    }

    private func handle(result: SFSpeechRecognitionResult?, error: (any Error)?, taskID id: Int) {
        let step: Step = lock.withLock {
            // Late callbacks from a replaced task, or anything after teardown, are ignored.
            guard id == taskID, !isTornDown else { return .ignore }
            if let result {
                let text = result.bestTranscription.formattedString
                if !text.isEmpty { taskHeardSomething = true }
                if result.isFinal {
                    transcript.commit(text)
                    return .taskEnded
                }
                transcript.setVolatile(text)
                return .partial(transcript.text)
            }
            guard error != nil else { return .ignore }
            // Ending audio with no speech, the time limit or a hiccup: keep what this task heard.
            transcript.commitVolatile()
            return .taskEnded
        }
        switch step {
        case .ignore: break
        case .partial(let text): yield(.partial(text))
        case .taskEnded: taskEnded()
        }
    }

    private enum Next {
        case finish(String)
        case restart(previous: SFSpeechAudioBufferRecognitionRequest?)
        case giveUp(String)
    }

    private func taskEnded() {
        let next: Next = lock.withLock {
            if finishRequested { return .finish(transcript.text) }
            let duration = Date.now.timeIntervalSince(taskStartedAt)
            switch restarts.taskEnded(after: duration, recognizedText: taskHeardSomething) {
            case .restart: return .restart(previous: request)
            case .stop: return .giveUp(transcript.text)
            }
        }
        switch next {
        case .finish(let text):
            yield(.final(text))
            teardown()
        case .restart(let previous):
            startTask()            // the tap feeds the new request from here on
            previous?.endAudio()
        case .giveUp(let text):
            yield(text.isEmpty ? .failed(String(localized: "Dictation stopped. Try again.")) : .final(text))
            teardown()
        }
    }

    private func finishWithCurrentText() {
        let text: String? = lock.withLock { isTornDown ? nil : transcript.text }
        guard let text else { return }
        yield(.final(text))
        teardown()
    }

    // MARK: Teardown

    private func yield(_ event: DictationEvent) {
        let continuation = lock.withLock { self.continuation }
        continuation?.yield(event)
    }

    private func stopAudio() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
    }

    private func teardown() {
        let released: (SFSpeechAudioBufferRecognitionRequest?, AsyncStream<DictationEvent>.Continuation?, (any NSObjectProtocol)?)? =
            lock.withLock {
                guard !isTornDown else { return nil }
                isTornDown = true
                defer {
                    self.request = nil
                    self.task = nil
                    self.continuation = nil
                    self.interruptionObserver = nil
                }
                return (self.request, self.continuation, self.interruptionObserver)
            }
        guard let released else { return }
        let (request, continuation, observer) = released
        stopAudio()
        request?.endAudio()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        continuation?.finish()
        DictationAudio.deactivateSession()
    }
}

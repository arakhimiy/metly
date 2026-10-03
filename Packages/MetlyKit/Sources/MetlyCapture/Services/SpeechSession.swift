import AVFAudio
import Foundation
import Speech

/// One on-device dictation run: AVAudioEngine microphone tap → SFSpeechAudioBufferRecognitionRequest.
/// Lives off the main actor (audio tap and recognizer callbacks run on background queues) and reports
/// through an `AsyncStream`. Audio is never written anywhere.
nonisolated final class SpeechSession: @unchecked Sendable {
    enum Event: Sendable {
        case partial(String)
        case final(String)
        case failed(String)
    }

    enum SessionError: Error {
        case noMicrophoneInput
    }

    private let recognizer: SFSpeechRecognizer
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var continuation: AsyncStream<Event>.Continuation?
    private var isTornDown = false
    private var finishRequested = false
    private var lastText = ""

    /// Nil when on-device recognition isn't available (PLAN Q17: on-device only).
    /// Tries the locale, then its language (e.g. "en_UZ" → "en"), then US English.
    init?(locale: Locale) {
        var candidates = [locale]
        if let language = locale.language.languageCode?.identifier {
            candidates.append(Locale(identifier: language))
        }
        candidates.append(Locale(identifier: "en-US"))
        let recognizer = candidates.lazy
            .compactMap { SFSpeechRecognizer(locale: $0) }
            .first { $0.isAvailable && $0.supportsOnDeviceRecognition }
        guard let recognizer else { return nil }
        self.recognizer = recognizer
    }

    func start() throws -> AsyncStream<Event> {
        let (stream, continuation) = AsyncStream.makeStream(of: Event.self)
        self.continuation = continuation

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            teardown()
            throw SessionError.noMicrophoneInput
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            teardown()
            throw error
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                self.remember(text)
                if result.isFinal {
                    continuation.yield(.final(text))
                    continuation.finish()
                    self.teardown()
                } else {
                    continuation.yield(.partial(text))
                }
            } else if error != nil {
                // Ending audio with no speech surfaces as an error — treat it as a normal finish.
                if self.wasFinishRequested {
                    continuation.yield(.final(self.rememberedText))
                } else {
                    continuation.yield(.failed("Dictation stopped. Try again."))
                }
                continuation.finish()
                self.teardown()
            }
        }

        continuation.onTermination = { [weak self] _ in self?.teardown() }
        return stream
    }

    /// Stops listening; the recognizer then delivers the final transcript.
    func finish() {
        lock.lock()
        finishRequested = true
        lock.unlock()
        stopAudio()
        request?.endAudio()
    }

    /// Stops immediately without a final result.
    func cancel() {
        task?.cancel()
        teardown()
    }

    // MARK: Private

    private var wasFinishRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return finishRequested
    }

    private var rememberedText: String {
        lock.lock()
        defer { lock.unlock() }
        return lastText
    }

    private func remember(_ text: String) {
        lock.lock()
        lastText = text
        lock.unlock()
    }

    private func stopAudio() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
    }

    private func teardown() {
        lock.lock()
        guard !isTornDown else {
            lock.unlock()
            return
        }
        isTornDown = true
        lock.unlock()

        stopAudio()
        request?.endAudio()
        request = nil
        task = nil
        continuation?.finish()
        continuation = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

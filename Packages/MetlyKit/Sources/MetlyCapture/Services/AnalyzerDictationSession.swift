import AVFAudio
import Foundation
import Speech

/// iOS 26+ dictation with `SpeechAnalyzer`: long-form, fully on-device, no one-minute task limit.
///
/// Uses `SpeechTranscriber` where the device and language support it, otherwise `DictationTranscriber`;
/// the on-device model is downloaded through `AssetInventory` the first time (the form shows "preparing").
/// Microphone buffers are converted to the analyzer's format and streamed in; volatile results are
/// replaced until a final result commits them (`TranscriptAccumulator`). Audio is never written anywhere.
@available(iOS 26, *)
nonisolated final class AnalyzerDictationSession: DictationSession, @unchecked Sendable {
    private enum Transcriber: Sendable {
        case speech(SpeechTranscriber)
        case dictation(DictationTranscriber)

        var module: any SpeechModule {
            switch self {
            case .speech(let transcriber): transcriber
            case .dictation(let transcriber): transcriber
            }
        }
    }

    private let transcriber: Transcriber
    private let engine = AVAudioEngine()
    private let lock = NSLock()

    // Guarded by `lock`.
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var output: AsyncStream<DictationEvent>.Continuation?
    private var converter: AudioBufferConverter?
    private var resultsTask: Task<Void, Never>?
    private var interruptionObserver: (any NSObjectProtocol)?
    private var transcript = TranscriptAccumulator()
    private var isFinishing = false
    private var isTornDown = false

    private init(_ transcriber: Transcriber) {
        self.transcriber = transcriber
    }

    /// A session for `locale` (then its language, then US English), or nil when SpeechAnalyzer has no
    /// model for it on this device — use `SpeechSession` then. Downloads the model if needed.
    static func make(locale: Locale) async -> AnalyzerDictationSession? {
        var candidates = [locale]
        if let language = locale.language.languageCode?.identifier {
            candidates.append(Locale(identifier: language))
        }
        candidates.append(Locale(identifier: "en-US"))

        // "en_UZ", "en" and "en-US" often resolve to the same model: try each one once (offline, every
        // failed attempt waits on the asset service).
        var tried = Set<String>()
        for candidate in candidates {
            if SpeechTranscriber.isAvailable, let supported = await SpeechTranscriber.supportedLocale(equivalentTo: candidate),
               tried.insert("speech:" + supported.identifier).inserted {
                let transcriber = SpeechTranscriber(locale: supported, preset: .progressiveTranscription)
                if await installModel(for: transcriber) { return AnalyzerDictationSession(.speech(transcriber)) }
            }
            if let supported = await DictationTranscriber.supportedLocale(equivalentTo: candidate),
               tried.insert("dictation:" + supported.identifier).inserted {
                let transcriber = DictationTranscriber(locale: supported, preset: .progressiveLongDictation)
                if await installModel(for: transcriber) { return AnalyzerDictationSession(.dictation(transcriber)) }
            }
        }
        return nil
    }

    private static func installModel(for module: any SpeechModule) async -> Bool {
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                try await request.downloadAndInstall()
            }
            return await AssetInventory.status(forModules: [module]) == .installed
        } catch {
            return false
        }
    }

    // MARK: DictationSession

    func start() async throws -> AsyncStream<DictationEvent> {
        let module = transcriber.module
        let (stream, output) = AsyncStream.makeStream(of: DictationEvent.self)
        let (inputSequence, input) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let analyzer = SpeechAnalyzer(modules: [module])
        lock.withLock {
            self.output = output
            self.input = input
            self.analyzer = analyzer
        }
        output.onTermination = { [weak self] termination in
            if case .cancelled = termination { self?.cancel() }
        }

        do {
            try DictationAudio.activateSession()
            let inputNode = engine.inputNode
            let micFormat = inputNode.outputFormat(forBus: 0)
            guard micFormat.channelCount > 0, micFormat.sampleRate > 0 else { throw DictationSessionError.noMicrophoneInput }
            let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module], considering: micFormat)
                ?? micFormat
            let converter = try AudioBufferConverter(from: micFormat, to: analyzerFormat)
            try await analyzer.prepareToAnalyze(in: analyzerFormat)
            try checkStillWanted()

            let results = Task { [weak self] in
                guard let self else { return }
                await self.consumeResults()
            }
            lock.withLock {
                self.converter = converter
                resultsTask = results
            }
            try await analyzer.start(inputSequence: inputSequence)
            try checkStillWanted()

            inputNode.installTap(onBus: 0, bufferSize: 4096, format: micFormat) { [weak self] buffer, _ in
                self?.feed(buffer)
            }
            engine.prepare()
            try engine.start()
        } catch {
            cancel()
            throw error
        }

        let observer = DictationAudio.observeInterruptions { [weak self] in self?.finish() }
        lock.withLock { interruptionObserver = observer }
        return stream
    }

    /// Stops the microphone and lets the analyzer finalize what it heard; the final transcript follows.
    func finish() {
        let (input, analyzer): (AsyncStream<AnalyzerInput>.Continuation?, SpeechAnalyzer?) = lock.withLock {
            guard !isTornDown, !isFinishing else { return (nil, nil) }
            isFinishing = true
            return (self.input, self.analyzer)
        }
        stopAudio()
        input?.finish()
        guard let analyzer else { return }
        Task { [weak self] in
            do {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            } catch {
                await analyzer.cancelAndFinishNow()
            }
            // The results stream normally ends right after finalizing; don't wait on it forever.
            try? await Task.sleep(for: .seconds(3))
            self?.finishWithCurrentText()
        }
    }

    /// Stops immediately without a final result.
    func cancel() {
        let (analyzer, results): (SpeechAnalyzer?, Task<Void, Never>?) = lock.withLock { (self.analyzer, resultsTask) }
        results?.cancel()
        teardown()
        if let analyzer {
            Task { await analyzer.cancelAndFinishNow() }
        }
    }

    // MARK: Audio in

    private func feed(_ buffer: AVAudioPCMBuffer) {
        let (input, converter) = lock.withLock { (self.input, self.converter) }
        guard let input, let converter, let converted = converter.convert(buffer) else { return }
        input.yield(AnalyzerInput(buffer: converted))
    }

    private func checkStillWanted() throws {
        let stopped = lock.withLock { isFinishing || isTornDown }
        if stopped { throw DictationSessionError.stoppedWhileStarting }
    }

    // MARK: Results out

    private func consumeResults() async {
        do {
            switch transcriber {
            case .speech(let transcriber):
                for try await result in transcriber.results {
                    receive(String(result.text.characters), isFinal: result.isFinal)
                }
            case .dictation(let transcriber):
                for try await result in transcriber.results {
                    receive(String(result.text.characters), isFinal: result.isFinal)
                }
            }
            finishWithCurrentText()
        } catch {
            let text: String? = lock.withLock { isTornDown ? nil : transcript.text }
            if let text {
                send(text.isEmpty ? .failed(String(localized: "Dictation stopped. Try again.")) : .final(text))
            }
            teardown()
        }
    }

    private func receive(_ text: String, isFinal: Bool) {
        let current: String? = lock.withLock {
            guard !isTornDown else { return nil }
            if isFinal {
                transcript.commit(text)
            } else {
                transcript.setVolatile(text)
            }
            return transcript.text
        }
        if let current { send(.partial(current)) }
    }

    private func finishWithCurrentText() {
        let text: String? = lock.withLock { isTornDown ? nil : transcript.text }
        guard let text else { return }
        send(.final(text))
        teardown()
    }

    private func send(_ event: DictationEvent) {
        let output = lock.withLock { self.output }
        output?.yield(event)
    }

    // MARK: Teardown

    private func stopAudio() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
    }

    private func teardown() {
        let released: (AsyncStream<AnalyzerInput>.Continuation?, AsyncStream<DictationEvent>.Continuation?, (any NSObjectProtocol)?)? =
            lock.withLock {
                guard !isTornDown else { return nil }
                isTornDown = true
                defer {
                    self.input = nil
                    self.output = nil
                    self.converter = nil
                    self.resultsTask = nil
                    self.interruptionObserver = nil
                }
                return (self.input, self.output, self.interruptionObserver)
            }
        guard let released else { return }
        let (input, output, observer) = released
        stopAudio()
        input?.finish()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        output?.finish()
        DictationAudio.deactivateSession()
    }
}

/// Converts microphone buffers to the analyzer's format (sample rate / channel layout). Used only from the
/// audio tap's thread; the converter keeps its resampling state between buffers.
nonisolated final class AudioBufferConverter: @unchecked Sendable {
    private let converter: AVAudioConverter?
    private let outputFormat: AVAudioFormat

    init(from inputFormat: AVAudioFormat, to outputFormat: AVAudioFormat) throws {
        self.outputFormat = outputFormat
        if inputFormat == outputFormat {
            converter = nil
        } else if let converter = AVAudioConverter(from: inputFormat, to: outputFormat) {
            converter.primeMethod = .none
            self.converter = converter
        } else {
            throw DictationSessionError.noMicrophoneInput
        }
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter else { return buffer }
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let converted = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return nil }
        let source = OneShotBuffer(buffer)
        var error: NSError?
        let status = converter.convert(to: converted, error: &error) { _, inputStatus in
            guard let next = source.take() else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            inputStatus.pointee = .haveData
            return next
        }
        guard status != .error, error == nil, converted.frameLength > 0 else { return nil }
        return converted
    }
}

/// Hands one buffer to `AVAudioConverter`'s (Sendable) input block exactly once.
private nonisolated final class OneShotBuffer: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func take() -> AVAudioPCMBuffer? {
        defer { buffer = nil }
        return buffer
    }
}

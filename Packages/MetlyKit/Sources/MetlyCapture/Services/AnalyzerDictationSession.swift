import AVFAudio
import Foundation
import Speech

/// iOS 26+ dictation with `SpeechAnalyzer`: long-form, fully on-device, no one-minute task limit.
///
/// Uses `SpeechTranscriber` where the device and language support it, otherwise `DictationTranscriber`;
/// the on-device model is downloaded through `AssetInventory` the first time (the form shows the progress).
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

    enum Preparation: Sendable {
        case ready(AnalyzerDictationSession)
        /// SpeechAnalyzer has no model for the language on this device — try `SpeechSession`.
        case unsupported
        /// A model exists but the system couldn't download it (offline, no space).
        case downloadFailed
    }

    /// A session for exactly `locale` (never another language). The on-device model is downloaded by the
    /// system through `AssetInventory` when it isn't installed yet; `progress` reports 0…1 while it does.
    static func prepare(locale: Locale, progress: @escaping @Sendable (Double?) async -> Void) async -> Preparation {
        var candidates: [Transcriber] = []
        if SpeechTranscriber.isAvailable, let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale),
           DictationLocale.isSameLanguage(supported, as: locale) {
            candidates.append(.speech(SpeechTranscriber(locale: supported, preset: .progressiveTranscription)))
        }
        if let supported = await DictationTranscriber.supportedLocale(equivalentTo: locale),
           DictationLocale.isSameLanguage(supported, as: locale) {
            candidates.append(.dictation(DictationTranscriber(locale: supported, preset: .progressiveLongDictation)))
        }

        var downloadFailed = false
        for candidate in candidates {
            switch await installModel(for: candidate.module, locale: locale, progress: progress) {
            case .installed: return .ready(AnalyzerDictationSession(candidate))
            case .failed: downloadFailed = true
            case .unsupported: continue
            }
        }
        return downloadFailed ? .downloadFailed : .unsupported
    }

    private enum Installation { case installed, failed, unsupported }

    private static func installModel(for module: any SpeechModule, locale: Locale,
                                     progress: @escaping @Sendable (Double?) async -> Void) async -> Installation {
        switch await AssetInventory.status(forModules: [module]) {
        case .installed: return .installed
        case .unsupported: return .unsupported
        case .supported, .downloading: break
        @unknown default: break
        }
        do {
            await makeRoomForReservation(of: locale)
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                await progress(request.progress.totalUnitCount > 0 ? request.progress.fractionCompleted : nil)
                let reporter = Task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(250))
                        await progress(request.progress.totalUnitCount > 0 ? request.progress.fractionCompleted : nil)
                    }
                }
                defer { reporter.cancel() }
                try await request.downloadAndInstall()
            }
            return await AssetInventory.status(forModules: [module]) == .installed ? .installed : .failed
        } catch {
            return .failed
        }
    }

    /// The app may keep only `maximumReservedLocales` speech languages: switching Russian ↔ English releases
    /// the other one when the limit is reached (the system keeps the files if another app uses them).
    private static func makeRoomForReservation(of locale: Locale) async {
        let reserved = await AssetInventory.reservedLocales
        guard !reserved.contains(where: { DictationLocale.isSameLocale($0, locale) }),
              reserved.count >= AssetInventory.maximumReservedLocales else { return }
        for other in reserved.prefix(reserved.count - AssetInventory.maximumReservedLocales + 1) {
            await AssetInventory.release(reservedLocale: other)
        }
    }

    // MARK: DictationSession

    func start(vocabulary: [String]) async throws -> AsyncStream<DictationEvent> {
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
            if !vocabulary.isEmpty {
                let context = AnalysisContext()
                context.contextualStrings[.general] = vocabulary
                try? await analyzer.setContext(context)
            }
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
                send(text.isEmpty ? .failed(String(localized: "Dictation stopped. Try again.", bundle: .appStrings)) : .final(text))
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

import AVFoundation
import NaturalLanguage
import CSherpaOnnx

/// En indlæst Piper-model. Syntesen er blokerende og kaldes fra én seriel kø ad gangen.
final class PiperModel: @unchecked Sendable {
    private let tts: OpaquePointer
    let sampleRate: Double

    /// - Parameter directory: mappe med `*.onnx`, `tokens.txt` og `espeak-ng-data/`.
    init?(directory: URL) {
        let fm = FileManager.default
        guard let model = (try? fm.contentsOfDirectory(atPath: directory.path))?.first(where: { $0.hasSuffix(".onnx") }) else {
            return nil
        }
        var config = SherpaOnnxOfflineTtsConfig()
        memset(&config, 0, MemoryLayout<SherpaOnnxOfflineTtsConfig>.size)

        let created: OpaquePointer? = directory.appendingPathComponent(model).path.withCString { modelPath in
            directory.appendingPathComponent("tokens.txt").path.withCString { tokensPath in
                directory.appendingPathComponent("espeak-ng-data").path.withCString { dataPath in
                    "cpu".withCString { provider in
                        config.model.vits.model = modelPath
                        config.model.vits.tokens = tokensPath
                        config.model.vits.data_dir = dataPath
                        config.model.vits.noise_scale = 0.667
                        config.model.vits.noise_scale_w = 0.8
                        config.model.vits.length_scale = 1.0
                        config.model.num_threads = 2
                        config.model.provider = provider
                        config.max_num_sentences = 1
                        return SherpaOnnxCreateOfflineTts(&config)
                    }
                }
            }
        }
        guard let created else { return nil }
        tts = created
        sampleRate = Double(SherpaOnnxOfflineTtsSampleRate(created))
    }

    deinit { SherpaOnnxDestroyOfflineTts(tts) }

    /// - Parameter speed: 1.0 = normal; højere er hurtigere.
    func synthesize(_ text: String, speed: Float) -> [Float] {
        guard let audio = SherpaOnnxOfflineTtsGenerate(tts, text, 0, speed) else { return [] }
        defer { SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio) }
        guard audio.pointee.n > 0, let samples = audio.pointee.samples else { return [] }
        return Array(UnsafeBufferPointer(start: samples, count: Int(audio.pointee.n)))
    }
}

/// Piper-stemmer (neural, lokal). Teksten syntetiseres sætning for sætning på en baggrundskø,
/// så afspilningen begynder, så snart første sætning er klar.
@MainActor
public final class PiperSpeechEngine: SpeechEngine {
    public let engineID = "piper"
    /// 0…1. Sættes til 0 ved lydløse målinger.
    public var volume: Float = 1 { didSet { player.volume = volume } }

    private let store: VoiceStore
    private let synthesisQueue = DispatchQueue(label: "baymow.piper", qos: .userInitiated)
    private var models: [String: PiperModel] = [:]

    private let audioEngine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var connectedSampleRate: Double = 0

    /// Identificerer det aktuelle `speak`-kald. Alt arbejde fra tidligere kald ignoreres.
    private var jobID = UUID()
    private var cancellation = CancellationFlag()
    private var handler: ((SpeechEvent) -> Void)?

    public init(store: VoiceStore = VoiceStore()) {
        self.store = store
        audioEngine.attach(player)
    }

    public func installedVoices() -> [Voice] {
        store.installed().filter { $0.engineID == engineID }.map {
            Voice(id: $0.id, name: $0.name, language: $0.language, locale: $0.locale, quality: .neural, engineID: engineID,
                  isApprovedDefault: $0.isApprovedDefault)
        }
    }

    /// Indlæser modellen på forhånd, så første oplæsning ikke skal vente på det.
    public func prepare(_ voice: Voice) {
        guard models[voice.id] == nil else { return }
        let directory = store.directory(for: voice.id)
        // Indlæsning tager et øjeblik, men sker kun én gang pr. stemme.
        if let model = PiperModel(directory: directory) { models[voice.id] = model }
    }

    /// Frigiver en model, fx når stemmen fjernes.
    public func unload(voiceID: String) { models[voiceID] = nil }

    public func speak(_ text: String, voice: Voice, rate: Double, onEvent: @escaping (SpeechEvent) -> Void) {
        stop()
        prepare(voice)
        guard let model = models[voice.id], configureAudio(sampleRate: model.sampleRate) else {
            onEvent(.failed)
            return
        }
        let job = UUID()
        jobID = job
        handler = onEvent
        let cancellation = CancellationFlag()
        self.cancellation = cancellation

        let sentences = Self.sentences(in: text)
        guard !sentences.isEmpty else {
            onEvent(.finished)
            return
        }
        let format = AVAudioFormat(standardFormatWithSampleRate: model.sampleRate, channels: 1)!
        let speed = Float(rate)
        let lastIndex = sentences.count - 1

        synthesisQueue.async { [weak self] in
            for (index, sentence) in sentences.enumerated() {
                // Afbrudt? Så spild ikke tid på resten.
                guard let self, !cancellation.isCancelled else { return }
                let samples = model.synthesize(sentence.text, speed: speed)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self.enqueue(samples, format: format, job: job, index: index, isLast: index == lastIndex,
                                     nextOffset: index < lastIndex ? sentences[index + 1].utf16Offset : nil)
                    }
                }
            }
        }
    }

    public func pause() { player.pause() }

    public func resume() { if handler != nil { player.play() } }

    public func stop() {
        cancellation.cancel()
        jobID = UUID()
        handler = nil
        player.stop()
    }

    // MARK: - Internt

    private func enqueue(_ samples: [Float], format: AVAudioFormat, job: UUID, index: Int, isLast: Bool, nextOffset: Int?) {
        guard jobID == job else { return }
        guard !samples.isEmpty, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            if index == 0 { finish(job, with: .failed) } else if isLast { finish(job, with: .finished) }
            return
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData![0].update(from: source.baseAddress!, count: samples.count)
        }
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.jobID == job else { return }
                    if isLast {
                        self.finish(job, with: .finished)
                    } else if let nextOffset {
                        self.handler?(.progress(utf16Offset: nextOffset))
                    }
                }
            }
        }
        if index == 0 {
            player.play()
            handler?(.started)
        }
    }

    private func finish(_ job: UUID, with event: SpeechEvent) {
        guard jobID == job, let handler else { return }
        self.handler = nil
        jobID = UUID()
        handler(event)
    }

    private func configureAudio(sampleRate: Double) -> Bool {
        if connectedSampleRate != sampleRate {
            audioEngine.stop()
            let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
            audioEngine.connect(player, to: audioEngine.mainMixerNode, format: format)
            connectedSampleRate = sampleRate
        }
        player.volume = volume
        if !audioEngine.isRunning {
            do { try audioEngine.start() } catch { return false }
        }
        return true
    }

    /// Sætninger med deres UTF-16-startposition i teksten.
    static func sentences(in text: String) -> [(text: String, utf16Offset: Int)] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var result: [(String, Int)] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range])
            if !sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append((sentence, text.utf16.distance(from: text.utf16.startIndex, to: range.lowerBound)))
            }
            return true
        }
        return result
    }
}

/// Trådsikkert flag, som baggrundssyntesen tjekker mellem sætninger.
final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
    }
}

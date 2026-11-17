import Foundation
import CSherpaOnnx
import BaymowCore

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

/// Piper-stemmer (neural, lokal) som backend. Afspilningen ligger i `BackendSpeechEngine`/`PCMPlayer`.
///
/// Bemærk licens: udtalen laves af espeak-ng (GPL-3.0) via sherpa-onnx 1.x. Se docs/PROJEKTPLAN.md, B8.
public final class PiperBackend: SynthesisBackend, @unchecked Sendable {
    public let backendID = "piper"
    public let requiresNetwork = false

    private let store: VoiceStore
    private let lock = NSLock()
    private var models: [String: PiperModel] = [:]

    public init(store: VoiceStore = VoiceStore()) {
        self.store = store
    }

    public func installedVoices() -> [Voice] {
        store.installed().filter { $0.engineID == backendID }.map {
            Voice(id: $0.id, name: $0.name, language: $0.language, locale: $0.locale, quality: .neural, engineID: backendID,
                  isApprovedDefault: $0.isApprovedDefault)
        }
    }

    public func pronunciationOverrides(for language: Language) -> [String: String] {
        language == .danish ? Self.danishOverrides : [:]
    }

    /// Engelske ord, som den danske Piper-stemme udtaler forkert, og stavemåder, der blev genkendt
    /// rigtigt af talegenkendelsen i en ordprøve (16. november 2026, tools/stemmetest/word_probe.py).
    /// Virkning på hele sætninger: 14 → 18 af 30 rigtige, tegnfejl 8,4 % → 6,4 %. Beskeden, og ikke
    /// bedømt af et menneske. Ikke løst: "nice", "Apple", "webshop". Se docs/afleveringer/AP-24.md.
    static let danishOverrides: [String: String] = [
        "chrome": "krovm", "cloud": "klawd", "update": "opdæjt", "website": "vebsajt", "youtube": "jutjub",
        "iphone": "ajfon", "powerpoint": "pauerpojnt", "slack": "slagk", "feedback": "fidbæk",
        "smartphone": "smartfon", "login": "log in", "gaming": "gejming", "like": "lajk",
        "instagram": "instagræm", "messenger": "mæssendsjer", "chatgpt": "chat G P T", "safari": "sa-fari",
        "android": "androjd", "screenshot": "skrinsjot", "touchscreen": "totj-skrin",
    ]

    public func prepare(_ voice: Voice) { _ = model(for: voice.id) }

    public func synthesize(_ sentence: String, voice: Voice, rate: Double) throws -> PCMChunk {
        guard let model = model(for: voice.id) else { throw PiperError.modelUnavailable }
        return PCMChunk(samples: model.synthesize(sentence, speed: Float(rate)), sampleRate: model.sampleRate)
    }

    /// Frigiver en model, fx når stemmen fjernes.
    public func unload(voiceID: String) {
        lock.lock(); defer { lock.unlock() }
        models[voiceID] = nil
    }

    /// Indlæsning tager et øjeblik, men sker kun én gang pr. stemme.
    private func model(for voiceID: String) -> PiperModel? {
        lock.lock(); defer { lock.unlock() }
        if let loaded = models[voiceID] { return loaded }
        let model = PiperModel(directory: store.directory(for: voiceID))
        models[voiceID] = model
        return model
    }

    enum PiperError: Error { case modelUnavailable }
}

import Foundation
import NaturalLanguage

/// En bid mono-lyd i intervallet -1…1.
public struct PCMChunk: Sendable {
    public let samples: [Float]
    public let sampleRate: Double

    public init(samples: [Float], sampleRate: Double) {
        self.samples = samples
        self.sampleRate = sampleRate
    }
}

/// Laver lyd af tekst og ved intet om afspilning. Piper er en backend; cloud-tjenester og andre
/// lokale modeller bliver det også.
///
/// En ny stemmemotor er en ny type, der opfylder denne protokol, pakket ind i en
/// `BackendSpeechEngine` og registreret i `AppShell`. Kernen skal ikke ændres.
public protocol SynthesisBackend: AnyObject, Sendable {
    var backendID: String { get }
    /// `true` for cloud-tjenester. Sådan en backend må kun bruges efter brugerens udtrykkelige tilvalg.
    var requiresNetwork: Bool { get }
    func installedVoices() -> [Voice]
    /// Som `SpeechEngine.pronunciationOverrides(for:)`. Tom som standard.
    func pronunciationOverrides(for language: Language) -> [String: String]
    /// Indlæser det, stemmen skal bruge, så første sætning ikke skal vente. Må blokere.
    func prepare(_ voice: Voice)
    /// Én sætning ind, lyd ud. Må blokere; kaldes aldrig på hovedtråden.
    /// - Parameter rate: hastighedsfaktor, 1.0 = normal.
    func synthesize(_ sentence: String, voice: Voice, rate: Double) throws -> PCMChunk
}

public extension SynthesisBackend {
    func pronunciationOverrides(for language: Language) -> [String: String] { [:] }
    func prepare(_ voice: Voice) {}
}

/// Det, `BackendSpeechEngine` har brug for af en lydafspiller. `PCMPlayer` er den rigtige;
/// tests bruger en falsk.
@MainActor
public protocol PCMOutput: AnyObject {
    var volume: Float { get set }
    /// Sætter en bid i kø. `onPlayed` kaldes på hovedtråden, når bidden er afspillet til ende –
    /// men aldrig for bidder, der blev fjernet af `stop()`.
    /// - Returns: `false`, hvis lyden ikke kunne sættes i kø.
    func enqueue(_ chunk: PCMChunk, onPlayed: @escaping () -> Void) -> Bool
    func play()
    func pause()
    /// Stopper og tømmer køen.
    func stop()
}

/// Gør en `SynthesisBackend` til en `SpeechEngine`.
///
/// Teksten deles i sætninger, som syntetiseres én ad gangen på en baggrundskø og sendes til
/// afspilleren, så oplæsningen begynder, så snart første sætning er klar.
///
/// Overholder kernens regel: efter `stop()` eller et nyt `speak()` sendes ingen events fra det
/// forrige kald.
@MainActor
public final class BackendSpeechEngine: SpeechEngine {
    public var engineID: String { backend.backendID }
    /// 0…1. Sættes til 0 ved lydløse målinger.
    public var volume: Float {
        get { output.volume }
        set { output.volume = newValue }
    }

    private let backend: SynthesisBackend
    private let output: PCMOutput
    private let synthesisQueue: DispatchQueue

    /// Tilstanden for det aktuelle `speak`-kald. Erstattes ved hvert nyt kald og nulstilles ved stop.
    private final class Job {
        let handler: (SpeechEvent) -> Void
        let offsets: [Int]
        let cancellation = CancellationFlag()
        var started = false
        var synthesisDone = false
        var enqueued = 0
        var played = 0

        init(handler: @escaping (SpeechEvent) -> Void, offsets: [Int]) {
            self.handler = handler
            self.offsets = offsets
        }
    }

    private var job: Job?
    private var isPaused = false

    public init(backend: SynthesisBackend, output: PCMOutput? = nil,
                synthesisQueue: DispatchQueue = DispatchQueue(label: "baymow.synthesis", qos: .userInitiated)) {
        self.backend = backend
        self.output = output ?? PCMPlayer()
        self.synthesisQueue = synthesisQueue
    }

    public func installedVoices() -> [Voice] { backend.installedVoices() }

    public func pronunciationOverrides(for language: Language) -> [String: String] {
        backend.pronunciationOverrides(for: language)
    }

    /// Indlæser stemmen i baggrunden, så første oplæsning starter hurtigt.
    public func prepare(_ voice: Voice) {
        let backend = self.backend
        synthesisQueue.async { backend.prepare(voice) }
    }

    public func speak(_ text: String, voice: Voice, rate: Double, onEvent: @escaping (SpeechEvent) -> Void) {
        stop()
        let sentences = Self.sentences(in: text)
        guard !sentences.isEmpty else {
            onEvent(.finished)
            return
        }
        let job = Job(handler: onEvent, offsets: sentences.map(\.utf16Offset))
        self.job = job
        isPaused = false

        let backend = self.backend
        let cancellation = job.cancellation
        let lastIndex = sentences.count - 1
        synthesisQueue.async { [weak self] in
            for (index, sentence) in sentences.enumerated() {
                // Afbrudt? Så spild hverken tid eller (for cloud) penge på resten.
                if cancellation.isCancelled { return }
                let result = Result { try backend.synthesize(sentence.text, voice: voice, rate: rate) }
                if cancellation.isCancelled { return }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.receive(result, for: job, index: index, isLast: index == lastIndex)
                    }
                }
                if case .failure = result { return }
            }
        }
    }

    public func pause() {
        guard job != nil else { return }
        isPaused = true
        output.pause()
    }

    public func resume() {
        guard let job else { return }
        isPaused = false
        if job.started { output.play() }
    }

    public func stop() {
        job?.cancellation.cancel()
        job = nil
        isPaused = false
        output.stop()
    }

    // MARK: - Internt

    private func receive(_ result: Result<PCMChunk, Error>, for job: Job, index: Int, isLast: Bool) {
        guard self.job === job else { return }
        if isLast { job.synthesisDone = true }

        switch result {
        case .failure:
            end(job, with: .failed)
            return
        case .success(let chunk) where !chunk.samples.isEmpty:
            let queued = output.enqueue(chunk) { [weak self] in self?.chunkPlayed(job, index: index) }
            guard queued else {
                end(job, with: .failed)
                return
            }
            job.enqueued += 1
            if !job.started {
                job.started = true
                if !isPaused { output.play() }
                job.handler(.started)
            }
        case .success:
            break // En sætning uden lyd (fx kun tegn) springes over.
        }
        finishIfDone(job)
    }

    private func chunkPlayed(_ job: Job, index: Int) {
        guard self.job === job else { return }
        job.played += 1
        if job.synthesisDone, job.played == job.enqueued {
            end(job, with: .finished)
        } else if index + 1 < job.offsets.count {
            job.handler(.progress(utf16Offset: job.offsets[index + 1]))
        }
    }

    /// Sidste sætning kan være tom; så afsluttes der her i stedet for i `chunkPlayed`.
    private func finishIfDone(_ job: Job) {
        guard job.synthesisDone, job.played == job.enqueued else { return }
        end(job, with: job.enqueued == 0 ? .failed : .finished)
    }

    private func end(_ job: Job, with event: SpeechEvent) {
        guard self.job === job else { return }
        job.cancellation.cancel()
        self.job = nil
        if case .failed = event { output.stop() }
        job.handler(event)
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

import Foundation
import Combine
import NaturalLanguage

/// Ejer den ene aktive oplæsningssession.
///
/// Sessionen holder sin egen kopi af teksten – kun i hukommelsen – og er derfor uafhængig af
/// kildeprogrammet. En ny session erstatter den gamle; der er ingen kø.
@MainActor
public final class ReadingSessionManager: ObservableObject {
    public enum State: Equatable, Sendable {
        case idle       // ingen session
        case speaking
        case paused
        case stopped    // stoppet af brugeren; teksten er stadig klar til genstart
        case finished   // læst til ende; teksten er stadig klar til genstart
    }

    @Published public private(set) var state: State = .idle
    @Published public private(set) var language: Language?
    @Published public private(set) var progress: Double = 0
    @Published public private(set) var sourceAppName: String?
    /// Det stykke af teksten (fra `textForDisplay()`), der læses lige nu: et ord, eller en sætning, hvis motoren kun
    /// melder sætninger. `nil`, når der ikke læses. Bruges af ordfremhævningen (I1).
    @Published public private(set) var highlightRange: NSRange?

    /// Længste tekst, der læses op: 200.000 tegn, ca. fire timers oplæsning (AP-21).
    public static let maxTextLength = 200_000

    public var hasSession: Bool { session != nil }

    /// Teksten til visning i tekstvinduet (I1). Udleveres kun her, til visning; den gemmes ingen steder.
    public func textForDisplay() -> String? { session?.displayText }

    private struct Session {
        let id = UUID()
        let chunks: [String]
        /// Hele teksten, som den vises: bidderne sat sammen. Positioner i `highlightRange` gælder denne tekst.
        let displayText: String
        let chunkStartOffsets: [Int]
        let totalLength: Int
        var chunkIndex = 0
        var offsetInChunk = 0
        var voice: Voice
        var sourceBundleID: String?
        var triggeredAt: Date?
    }

    private var session: Session?
    private var activeEngine: SpeechEngine?
    /// Sat, når hastighed eller sprog er ændret under pause: næste afspil starter bidden igen fra samme ord.
    private var respeakOnResume = false

    private let catalog: VoiceCatalog
    private let settings: SettingsStore
    private let diagnostics: DiagnosticsService
    private let languageDetection = LanguageDetectionService()

    public init(catalog: VoiceCatalog, settings: SettingsStore, diagnostics: DiagnosticsService) {
        self.catalog = catalog
        self.settings = settings
        self.diagnostics = diagnostics
    }

    /// Starter en ny session og erstatter en eventuel eksisterende.
    /// - Returns: en besked til brugeren, hvis oplæsningen ikke kunne starte.
    @discardableResult
    public func start(text: String, sourceAppName: String? = nil, sourceBundleID: String? = nil, triggeredAt: Date? = nil) -> Notice? {
        // En markering ved et uheld (fx ⌘A i en hel bog) skal give en venlig besked, ikke timevis af oplæsning.
        guard text.count <= Self.maxTextLength else {
            diagnostics.record(.textTooLong, sourceBundleID: sourceBundleID)
            return .tooLong
        }
        // Linjeskift og orddeling fra PDF'er må ikke give pauser midt i sætninger (AP-31).
        let text = LineBreakCleanup.clean(text)
        let language = settings.forcedLanguage
            ?? languageDetection.dominantLanguage(of: text, fallback: settings.preferredLanguage)
        guard let voice = catalog.voice(for: language) else {
            diagnostics.record(.noVoiceAvailable, sourceBundleID: sourceBundleID)
            return .noVoice(language)
        }
        let chunks = TextChunker.chunks(for: text)
        guard !chunks.isEmpty else { return .noSelection }

        close()

        var offsets: [Int] = []
        var total = 0
        for chunk in chunks {
            offsets.append(total)
            total += chunk.utf16.count
        }
        session = Session(chunks: chunks, displayText: chunks.joined(), chunkStartOffsets: offsets, totalLength: max(total, 1),
                          voice: voice, sourceBundleID: sourceBundleID, triggeredAt: triggeredAt)
        self.language = language
        self.sourceAppName = sourceAppName
        progress = 0
        speakCurrentChunk()
        return nil
    }

    public func pause() {
        guard state == .speaking else { return }
        activeEngine?.pause()
        state = .paused
    }

    public func resume() {
        guard state == .paused else { return }
        if respeakOnResume {
            speakCurrentChunk()
        } else {
            activeEngine?.resume()
            state = .speaking
        }
    }

    /// Afspil/pause-knappen: fortsætter, pauser eller starter forfra afhængigt af tilstanden.
    public func togglePlayPause() {
        switch state {
        case .speaking: pause()
        case .paused: resume()
        case .stopped, .finished: restart()
        case .idle: break
        }
    }

    /// Stopper oplæsningen, men beholder sessionen, så teksten kan genstartes.
    public func stop() {
        guard session != nil else { return }
        activeEngine?.stop()
        session?.chunkIndex = 0
        session?.offsetInChunk = 0
        progress = 0
        highlightRange = nil
        state = .stopped
    }

    public func restart() {
        guard session != nil else { return }
        activeEngine?.stop()
        session?.chunkIndex = 0
        session?.offsetInChunk = 0
        progress = 0
        speakCurrentChunk()
    }

    /// Ændrer hastigheden. Gælder straks: kan motoren skifte undervejs, fortsætter oplæsningen uden afbrydelse;
    /// ellers fortsætter den aktuelle bid fra det ord, der var nået.
    public func setRate(_ rate: Double) {
        let clamped = min(max(rate, SettingsStore.rateRange.lowerBound), SettingsStore.rateRange.upperBound)
        let rounded = (clamped * 10).rounded() / 10
        guard rounded != settings.rate else { return }
        settings.rate = rounded
        if (state == .speaking || state == .paused) && !respeakOnResume, activeEngine?.setRate(rounded) == true {
            return
        }
        respeakFromCurrentPosition()
    }

    /// Manuel tilsidesættelse af sproget for den aktuelle session.
    public func setLanguage(_ language: Language) {
        guard session != nil, language != self.language, let voice = catalog.voice(for: language) else { return }
        session?.voice = voice
        session?.offsetInChunk = 0
        self.language = language
        respeakFromCurrentPosition()
    }

    /// Afslutter sessionen og frigiver teksten.
    public func close() {
        activeEngine?.stop()
        activeEngine = nil
        session = nil
        language = nil
        sourceAppName = nil
        progress = 0
        highlightRange = nil
        state = .idle
    }

    // MARK: - Internt

    private func respeakFromCurrentPosition() {
        guard session != nil else { return }
        switch state {
        case .speaking:
            speakCurrentChunk()
        case .paused:
            // Fortsæt fra samme sted med de nye indstillinger, når brugeren trykker afspil.
            activeEngine?.stop()
            respeakOnResume = true
        case .idle, .stopped, .finished:
            break
        }
    }

    private func speakCurrentChunk() {
        guard let session, session.chunkIndex < session.chunks.count,
              let engine = catalog.engine(for: session.voice) else {
            state = session == nil ? .idle : .stopped
            return
        }
        if let activeEngine, activeEngine !== engine { activeEngine.stop() }
        activeEngine = engine
        respeakOnResume = false

        let spoken = spokenText(for: session.chunks[session.chunkIndex])
        let chunk = spoken as NSString
        let base = min(session.offsetInChunk, chunk.length)
        // Kobling mellem det, der siges, og det, der vises – til fremhævningen.
        let alignment = WordAlignment(original: session.chunks[session.chunkIndex], spoken: spoken)
        let wordLevel = engine.reportsWordProgress
        let chunkStart = session.chunkStartOffsets[session.chunkIndex]
        let highlight: (Int) -> NSRange? = { spokenOffset in
            let range = wordLevel ? alignment.originalRange(forSpokenOffset: spokenOffset)
                : Self.sentenceRange(in: spoken, at: spokenOffset).flatMap { alignment.originalRange(forSpokenRange: $0) }
            return range.map { NSRange(location: chunkStart + $0.location, length: $0.length) }
        }
        let remaining = chunk.substring(from: base)
        let sessionID = session.id
        let chunkIndex = session.chunkIndex

        state = .speaking
        engine.speak(remaining, voice: session.voice, rate: settings.rate) { [weak self] event in
            guard let self, let current = self.session, current.id == sessionID, current.chunkIndex == chunkIndex else { return }
            switch event {
            case .started:
                self.highlightRange = highlight(base)
                if let triggeredAt = current.triggeredAt {
                    let ms = Int(Date().timeIntervalSince(triggeredAt) * 1000)
                    self.diagnostics.record(.speechStarted, sourceBundleID: current.sourceBundleID, milliseconds: ms,
                                            voice: current.voice)
                    self.session?.triggeredAt = nil
                }
            case .progress(let offset):
                self.session?.offsetInChunk = base + offset
                self.highlightRange = highlight(base + offset) ?? self.highlightRange
                // Positionen er i den forberedte tekst, som kan være længere end originalen; derfor loftet.
                let chunkLength = current.chunks[chunkIndex].utf16.count
                let within = min(base + offset, chunkLength)
                self.progress = Double(current.chunkStartOffsets[chunkIndex] + within) / Double(current.totalLength)
            case .finished:
                self.advance()
            case .failed:
                self.diagnostics.record(.speechFailed, sourceBundleID: current.sourceBundleID)
                self.stop()
            }
        }
    }

    /// Teksten, som den skal siges. Dansk tekst forberedes (tal, datoer, forkortelser skrives ud).
    private func spokenText(for chunk: String) -> String {
        guard language == .danish else { return chunk }
        let prepared = DanishTextNormalizer.normalize(chunk)
        guard let voice = session?.voice, let engine = catalog.engine(for: voice) else { return prepared }
        // Engelske ord, som netop denne motor udtaler forkert, skrives, så den siger dem rigtigt.
        return PronunciationOverrides.apply(engine.pronunciationOverrides(for: .danish), to: prepared)
    }

    /// Sætningen i `text`, der indeholder `offset` (UTF-16).
    static func sentenceRange(in text: String, at offset: Int) -> NSRange? {
        var result: NSRange?
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let ns = NSRange(range, in: text)
            if NSMaxRange(ns) > offset { result = ns; return false }
            return true
        }
        return result
    }

    private func advance() {
        guard var session else { return }
        session.chunkIndex += 1
        session.offsetInChunk = 0
        if session.chunkIndex >= session.chunks.count {
            session.chunkIndex = 0
            self.session = session
            progress = 1
            highlightRange = nil
            state = .finished
        } else {
            self.session = session
            speakCurrentChunk()
        }
    }
}

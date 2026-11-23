import Foundation
import NaturalLanguage
import BaymowCore

/// Resultatet af en stavekontrol: teksten delt i stykker, så rettelserne kan vises og vælges.
struct SpellingResult: Equatable {
    var segments: [SpellingSegment]
    /// Hvem der rettede. Ved en fejl på internettet er det Macens egen hjælp (se `cloudProblem`).
    var source: SpellingSource
    var language: Language
    /// Sat, hvis internet-hjælpen var slået til, men ikke kunne bruges.
    var cloudProblem: CloudSpellingError?

    /// `true`, hvis en sprogmodel blev brugt; ellers kun stavekontrollen.
    var usedModel: Bool { source != .spellCheckerOnly }

    /// Teksten, som den bliver brugt.
    var text: String { segments.map(\.text).joined() }
    var changes: [SpellingSegment] { segments.filter { $0.kind != .same } }
}

/// Deler teksten i sætninger, lader modellen foreslå en rettelse til hver, og lader vagten afgøre resten.
@MainActor
final class SpellingAssistant {
    /// Længere tekster bliver ikke rettet: markér et mindre stykke.
    static let maximumLength = 4000

    private let corrector: SpellingCorrector?
    /// Bruges, hvis internet-hjælpen fejler (fx intet internet). Aldrig omvendt: Macens egen hjælp sender aldrig
    /// teksten videre af sig selv.
    private let fallback: SpellingCorrector?
    private let checker: WordChecker
    private let level: SpellingLevel

    init(corrector: SpellingCorrector?, fallback: SpellingCorrector? = nil, checker: WordChecker,
         level: SpellingLevel = .standard) {
        self.corrector = corrector
        self.fallback = fallback
        self.checker = checker
        self.level = level
    }

    /// Til stavetesten: modellens svar for hver sætning, før vagten har set det.
    private(set) var lastProposals: [String] = []

    func check(_ text: String, preferred: Language = .danish) async -> SpellingResult {
        let language = LanguageDetectionService().dominantLanguage(of: text, fallback: preferred)
        var segments: [SpellingSegment] = []
        var active = corrector
        var problem: CloudSpellingError?
        lastProposals = []

        for piece in Self.sentencePieces(of: text) {
            if !piece.isSentence {
                segments.append(SpellingSegment(id: 0, original: piece.text, text: piece.text, kind: .same))
                continue
            }
            var proposal: String?
            if let current = active {
                do {
                    proposal = try await current.correct(piece.text, language: language)
                } catch {
                    if case .cloud = current.source {
                        // Internettet svigtede: resten af teksten rettes af Macens egen hjælp, og vinduet siger det.
                        problem = error as? CloudSpellingError ?? .failed
                        active = fallback
                        proposal = try? await active?.correct(piece.text, language: language)
                    }
                }
            }
            lastProposals.append(proposal ?? piece.text)
            let trusted: Bool = { if case .cloud = active?.source { return true } else { return false } }()
            let spellGuard = SpellingGuard(checker: checker, trusted: trusted, level: level)
            segments += await resolveChoices(spellGuard.review(piece.text, proposal: proposal, language: language),
                                             using: active, language: language)
        }
        for index in segments.indices { segments[index].id = index }
        return SpellingResult(segments: segments, source: active?.source ?? .spellCheckerOnly, language: language,
                              cloudProblem: problem)
    }

    /// Ord, hvor stavekontrollen har flere bud: modellen vælger ud fra sætningen. Brugerens eget ord er også et valg
    /// ("ingen af dem passer"), så modellen ikke tvinges til at gætte. Uden model står ordet markeret med forslag.
    private func resolveChoices(_ sentence: [SpellingSegment], using corrector: SpellingCorrector?,
                                language: Language) async -> [SpellingSegment] {
        var segments = sentence
        guard let corrector else { return segments }
        for index in segments.indices where !segments[index].candidates.isEmpty {
            let segment = segments[index]
            let blanked = segments.enumerated().map { $0.offset == index ? "___" : $0.element.text }.joined()
            guard let chosen = try? await corrector.choose(in: blanked, candidates: segment.candidates + [segment.original],
                                                           language: language),
                  chosen != segment.original, segment.candidates.contains(chosen) else { continue }
            if segment.mayApplyChoice {
                segments[index].text = chosen
                segments[index].kind = .corrected
                segments[index].suggestions = Array(segment.candidates.filter { $0 != chosen }.prefix(2))
            } else {
                segments[index].suggestions = Array(([chosen] + segment.candidates.filter { $0 != chosen }).prefix(3))
            }
        }
        return segments
    }

    /// Teksten delt i sætninger og mellemrummene mellem dem, så intet går tabt, når den sættes sammen igen.
    static func sentencePieces(of text: String) -> [(text: String, isSentence: Bool)] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var pieces: [(String, Bool)] = []
        var position = text.startIndex
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = text[range]
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let start = sentence.range(of: trimmed)?.lowerBound else { return true }
            let end = text.index(start, offsetBy: trimmed.count)
            if position < start { pieces.append((String(text[position..<start]), false)) }
            pieces.append((trimmed, true))
            position = end
            return true
        }
        if position < text.endIndex { pieces.append((String(text[position...]), false)) }
        return pieces
    }
}

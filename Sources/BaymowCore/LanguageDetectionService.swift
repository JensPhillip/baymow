import Foundation
import NaturalLanguage

/// Finder hovedsproget i en tekst blandt de understøttede sprog.
public struct LanguageDetectionService: Sendable {
    public init() {}

    /// - Parameter fallback: bruges, når teksten er for kort eller tvetydig til et sikkert svar.
    public func dominantLanguage(of text: String, fallback: Language) -> Language {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = Language.allCases.map(\.nlLanguage)
        // Et lille skub mod brugerens foretrukne sprog afgør helt korte, tvetydige tekster.
        var hints: [NLLanguage: Double] = [:]
        for language in Language.allCases { hints[language.nlLanguage] = language == fallback ? 0.6 : 0.4 }
        recognizer.languageHints = hints
        recognizer.processString(String(text.prefix(3000)))

        guard let detected = recognizer.dominantLanguage,
              let language = Language.allCases.first(where: { $0.nlLanguage == detected }) else {
            return fallback
        }
        return language
    }
}

/// Deler tekst i bidder på hele sætninger.
///
/// Bidder gør, at hastighed og sprog kan ændres midt i en lang tekst uden at starte forfra,
/// og at fremtidige neurale motorer kan begynde afspilning, før hele teksten er syntetiseret.
public enum TextChunker {
    public static func chunks(for text: String, targetLength: Int = 500) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var chunks: [String] = []
        var current = ""
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range])
            if !current.isEmpty, current.count + sentence.count > targetLength {
                chunks.append(current)
                current = ""
            }
            current += sentence
            return true
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

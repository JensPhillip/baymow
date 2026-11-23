import AppKit
import BaymowCore

/// Ét stykke af den rettede tekst: et ord eller mellemrummet/tegnene mellem ord.
struct SpellingSegment: Identifiable, Equatable {
    enum Kind: Equatable {
        /// Uændret.
        case same
        /// Rettet af Baymow. `original` er det, brugeren skrev; brugeren kan fortryde eller vælge et andet forslag.
        case corrected
        /// Stavekontrollen kender ikke ordet, og Baymow er i tvivl: ordet står, som brugeren skrev det, med forslag.
        case uncertain
    }

    var id: Int
    /// Det, brugeren skrev.
    let original: String
    /// Det, der bliver brugt. Brugeren kan ændre det ved at vælge et forslag.
    var text: String
    var kind: Kind
    /// Andre ord, brugeren kan vælge.
    var suggestions: [String] = []
    /// Ord, som modellen skal vælge imellem ud fra sætningen (sat af vagten, afgjort af `SpellingAssistant`).
    var candidates: [String] = []
    /// Om modellens valg må bruges direkte. Ellers står brugerens ord, og valget bliver kun første forslag.
    var mayApplyChoice = false

    var isChanged: Bool { text != original }
}

/// Macens stavekontrol – bruges til at kende rigtige ord og til forslag.
@MainActor
protocol WordChecker {
    func isMisspelled(_ word: String, language: Language) -> Bool
    func guesses(for word: String, language: Language) -> [String]
}

@MainActor
struct SystemWordChecker: WordChecker {
    func isMisspelled(_ word: String, language: Language) -> Bool {
        let range = NSSpellChecker.shared.checkSpelling(of: word, startingAt: 0, language: language.rawValue, wrap: false,
                                                        inSpellDocumentWithTag: 0, wordCount: nil)
        return range.location != NSNotFound
    }

    func guesses(for word: String, language: Language) -> [String] {
        NSSpellChecker.shared.guesses(forWordRange: NSRange(location: 0, length: (word as NSString).length), in: word,
                                      language: language.rawValue, inSpellDocumentWithTag: 0) ?? []
    }
}

/// Vagten: lader kun små, plausible rettelser fra modellen igennem.
///
/// Modellen kan ændre meningen ("mælg" → "mel"), skrive sætningen om eller svare på et spørgsmål (målt 22. november
/// 2026). Derfor sammenlignes ord for ord:
/// - Et rigtigt ord ("tit") må kun skiftes til et ord, der er ét bogstav fra ("tid").
/// - Et forkert stavet ord må rettes, hvis rettelsen ligner det skrevne. Har stavekontrollen forslag, der ligner endnu
///   mere, skal modellen vælge blandt dem ud fra sætningen (det gør `SpellingAssistant`).
/// - Tilføjede ord og omskrivninger bruges ikke.
@MainActor
struct SpellingGuard {
    let checker: WordChecker
    /// Internet-modellerne (Claude, ChatGPT) må rette mere end Macens model: i stavetesten lavede de ingen forkerte
    /// rettelser, og Macens stavekontrol godkender selv forkerte ord som "ernagien" (målt 23. november 2026).
    /// Omskrivninger, tilføjede ord og svar på teksten bliver stadig ikke brugt.
    var trusted = false
    /// Hvor meget der må rettes. "Klarere sætninger" kræver `trusted` (internet-hjælpen).
    var level: SpellingLevel = .standard

    /// Hvor stor en del af ordene, der skal gå igen i modellens svar, før svaret overhovedet bruges.
    static let minimumSharedWords = 0.6
    /// Ved "klarere sætninger" må mere ændres; et svar på teksten deler stadig næsten ingen ord med den.
    static let minimumSharedWordsWhenClarifying = 0.4

    private var clarifying: Bool { trusted && level == .clarity }

    /// Tegnene mellem to ord: modellens (fx et nyt komma), hvis tegnsætning må rettes, og de kun er tegnsætning og
    /// mellemrum; ellers brugerens.
    func separator(_ original: String, _ model: String) -> String {
        guard level.fixesPunctuation, model != original else { return original }
        let allowed = CharacterSet(charactersIn: ",.;:!?…-–—\"'«»„“”‘’()").union(.whitespaces)
        guard model.unicodeScalars.allSatisfy(allowed.contains),
              model.contains("\n") == original.contains("\n"),
              model.count <= original.count + 3 else { return original }
        return model
    }

    enum Decision: Equatable {
        case keep
        case fix(String)
        /// Modellen skal vælge blandt disse ud fra sætningen. `apply`: valget må bruges direkte, fordi modellen selv
        /// rettede ordet, men stavekontrollen havde bud, der ligner det skrevne mere.
        case choose([String], apply: Bool)
    }

    /// Retter én sætning. `proposal` er modellens svar, eller `nil`, hvis der ikke er en model.
    func review(_ sentence: String, proposal: String?, language: Language) -> [SpellingSegment] {
        let original = Tokens(sentence)
        var out: [SpellingSegment] = []
        func add(_ originalText: String, _ text: String, _ kind: SpellingSegment.Kind = .same) {
            out.append(SpellingSegment(id: out.count, original: originalText, text: text, kind: kind))
        }
        /// Ét af brugerens ord, med eller uden modellens forslag.
        func word(_ i: Int, proposal: String?, separatorAfter: String) {
            let written = original.words[i]
            switch decide(written, proposal: proposal, language: language) {
            case .keep:
                add(written, written)
                add(original.separators[i + 1], original.separators[i + 1])
            case .fix(let fixed):
                add(written, fixed, fixed == written ? .same : .corrected)
                add(original.separators[i + 1], separator(original.separators[i + 1], separatorAfter)) // fx et komma
            case .choose(let candidates, let apply):
                out.append(SpellingSegment(id: out.count, original: written, text: written, kind: .uncertain,
                                           suggestions: Array(candidates.prefix(3)), candidates: candidates,
                                           mayApplyChoice: apply))
                add(original.separators[i + 1], original.separators[i + 1])
            }
        }

        let proposed = proposal.map(Tokens.init)
        let pairs = proposed.map { Self.matchingWords(original.words.map { $0.lowercased() }, $0.words.map { $0.lowercased() }) } ?? []
        let longest = max(original.words.count, proposed?.words.count ?? 0)
        let minimum = clarifying ? Self.minimumSharedWordsWhenClarifying : Self.minimumSharedWords
        guard let proposed, longest > 0, Double(pairs.count) / Double(longest) >= minimum else {
            // Ingen model, eller modellen har svaret på teksten i stedet for at rette den: kun stavekontrollen.
            add(original.separators[0], original.separators[0])
            for i in original.words.indices { word(i, proposal: nil, separatorAfter: original.separators[i + 1]) }
            return out
        }

        // Starten (fx anførselstegn) fra modellen, hvis første ord er fælles; ellers brugerens.
        let leading = pairs.first.map { $0 == (0, 0) } == true ? proposed.separators[0] : original.separators[0]
        add(original.separators[0], separator(original.separators[0], leading))

        var o = 0, p = 0
        for (matchO, matchP) in pairs + [(original.words.count, proposed.words.count)] {
            let oldWords = Array(o..<matchO), newWords = Array(p..<matchP)
            if !oldWords.isEmpty {
                if oldWords.count == newWords.count, oldWords.count <= 3 {
                    // Samme antal ord: hvert ord for sig.
                    for (i, j) in zip(oldWords, newWords) {
                        word(i, proposal: proposed.words[j], separatorAfter: proposed.separators[j + 1])
                    }
                } else if let joined = joinedFix(oldWords, newWords, original: original, proposed: proposed, language: language) {
                    // Ord, der er skrevet i to dele ("til bage" → "tilbage") eller omvendt.
                    add(joined.original, joined.fixed, .corrected)
                    add(original.separators[oldWords.last! + 1],
                        separator(original.separators[oldWords.last! + 1], proposed.separators[newWords.last! + 1]))
                } else if clarifying {
                    // "Klarere sætninger": hele stykket skiftes ud, og brugeren kan vælge sit eget igen.
                    let after = original.separators[oldWords.last! + 1]
                    add(phrase(oldWords, in: original), phrase(newWords, in: proposed), .corrected)
                    add(after, newWords.isEmpty ? "" : separator(after, proposed.separators[newWords.last! + 1]))
                } else {
                    // En omskrivning: brugerens ord bliver stående (stavekontrollen ser stadig på dem).
                    for i in oldWords { word(i, proposal: nil, separatorAfter: original.separators[i + 1]) }
                }
            }
            // Tilføjede ord fra modellen (oldWords tom) bruges ikke – undtagen ved "klarere sætninger", hvor de hæftes
            // på ordet før, så brugeren kan fravælge dem sammen med det.
            if oldWords.isEmpty, !newWords.isEmpty, clarifying, out.count >= 3 {
                let wordIndex = out.count - 2, separatorIndex = out.count - 1
                out[wordIndex].text += out[separatorIndex].text + phrase(newWords, in: proposed)
                out[wordIndex].kind = .corrected
                out[separatorIndex].text = separator(out[separatorIndex].original, proposed.separators[newWords.last! + 1])
            }
            if matchO < original.words.count {
                word(matchO, proposal: proposed.words[matchP], separatorAfter: proposed.separators[matchP + 1])
            }
            o = matchO + 1
            p = matchP + 1
        }
        // Sætningens slutning (fx "." eller "?"): modellens, hvis tegnsætning må rettes, og dens sidste ord også er
        // brugerens sidste ord. Ellers brugerens: modellen fortsætter af og til sætningen ("Vi ses kl." → "… kl. 10.").
        let endsTogether = pairs.last.map { $0 == (original.words.count - 1, proposed.words.count - 1) } ?? false
        // Ved "klarere sætninger" kan ordene flytte rundt; modellens slutning følger så med dens sidste ord.
        if !(clarifying || (endsTogether && level.fixesPunctuation)) {
            out[out.count - 1].text = out[out.count - 1].original
        }
        return out
    }

    /// Ordene med tegnene imellem, som de står i teksten.
    private func phrase(_ indices: [Int], in tokens: Tokens) -> String {
        indices.enumerated().map { k, i in tokens.words[i] + (k < indices.count - 1 ? tokens.separators[i + 1] : "") }.joined()
    }

    /// Hvad der skal ske med ét ord, brugeren har skrevet.
    func decide(_ written: String, proposal: String?, language: Language) -> Decision {
        let misspelled = checker.isMisspelled(written, language: language)
        let lower = written.lowercased()
        let proposalDistance = proposal.map { Self.distance(lower, $0.lowercased()) }
        let proposalIsWord = proposal.map { !checker.isMisspelled($0, language: language) } ?? false

        // Store bogstaver ("jeg" → "Jeg" først i sætningen) hører til tegnsætningen.
        if let proposal, proposal != written, proposal.lowercased() == lower {
            return level.fixesPunctuation ? .fix(proposal) : .keep
        }
        // "Klarere sætninger": internet-modellen må også skifte et ord ud med et andet.
        if clarifying, let proposal, let proposalDistance, proposalDistance > 0 { return .fix(proposal) }

        if trusted, let proposal, let proposalDistance, proposalDistance > 0 {
            // Internet-modellen: dens rettelse bruges, hvis den ligner det skrevne. Ingen grænse på ét bogstav for
            // rigtige ord ("vinde" → "finde", "ernagien" → "energien"), men stadig ingen udskiftning med et helt andet ord.
            if proposalDistance <= Self.allowedDistance(for: written) + 1 { return .fix(proposal) }
        }

        guard misspelled else {
            // Et rigtigt ord. Lange ord er undtaget fra grænsen på ét bogstav: stavekontrollen godkender mange forkert
            // stavede sammensatte ord ("restorangen").
            guard let proposal, let proposalDistance, proposalIsWord else { return .keep }
            let limit = written.count >= 8 ? Self.allowedDistance(for: written) : 1
            return proposalDistance <= limit ? .fix(proposal) : .keep
        }

        let guesses = Self.unique(checker.guesses(for: written, language: language), excluding: written)
            .map { (word: $0, distance: Self.distance(lower, $0.lowercased())) }
            .filter { $0.distance <= Self.allowedDistance(for: written) }
        if let proposal, let proposalDistance, proposalIsWord, proposalDistance > 0,
           proposalDistance <= Self.allowedDistance(for: written) {
            let closer = guesses.filter { $0.distance < proposalDistance }
            if closer.isEmpty { return .fix(proposal) }
            // Stavekontrollen har ord, der ligner det skrevne mere ("mælg": "mælk", "mægl" … frem for "mel").
            return .choose(closer.sorted { $0.distance < $1.distance }.map { Self.matchCase($0.word, like: written) },
                           apply: true)
        }
        // Modellen lod ordet stå eller foreslog noget, der ikke ligner: Baymow retter ikke selv, men viser forslag.
        if guesses.isEmpty { return .keep }
        return .choose(guesses.sorted { $0.distance < $1.distance }.map { Self.matchCase($0.word, like: written) },
                       apply: false)
    }

    private func joinedFix(_ oldWords: [Int], _ newWords: [Int], original: Tokens, proposed: Tokens,
                           language: Language) -> (original: String, fixed: String)? {
        guard oldWords.count <= 3, !newWords.isEmpty, newWords.count <= 3 else { return nil }
        let written = oldWords.map { original.words[$0] }.joined()
        let fixed = newWords.map { proposed.words[$0] }
        guard Self.distance(written.lowercased(), fixed.joined().lowercased()) <= 1,
              trusted || fixed.allSatisfy({ !checker.isMisspelled($0, language: language) }) else { return nil }
        let originalText = oldWords.enumerated().map { k, i in
            original.words[i] + (k < oldWords.count - 1 ? original.separators[i + 1] : "")
        }.joined()
        let fixedText = newWords.enumerated().map { k, j in
            proposed.words[j] + (k < newWords.count - 1 ? proposed.separators[j + 1] : "")
        }.joined()
        return (originalText, fixedText)
    }

    // MARK: Hjælpere

    /// Hvor mange bogstaver en rettelse må ændre: små fejl i korte ord, lidt mere i lange.
    static func allowedDistance(for word: String) -> Int {
        switch word.count {
        case ..<9: return 2
        case ..<13: return 3
        default: return 4
        }
    }

    /// Antal bogstaver, der skal skiftes, tilføjes, fjernes eller byttes om (Damerau-Levenshtein).
    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var d = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }
        for j in 0...b.count { d[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                }
            }
        }
        return d[a.count][b.count]
    }

    /// Par af fælles ord i rækkefølge (længste fælles delfølge).
    static func matchingWords(_ a: [String], _ b: [String]) -> [(Int, Int)] {
        guard !a.isEmpty, !b.isEmpty else { return [] }
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var pairs: [(Int, Int)] = []
        var i = 0, j = 0
        while i < a.count, j < b.count {
            if a[i] == b[j] { pairs.append((i, j)); i += 1; j += 1 }
            else if table[i + 1][j] >= table[i][j + 1] { i += 1 }
            else { j += 1 }
        }
        return pairs
    }

    static func unique(_ words: [String], excluding word: String) -> [String] {
        var seen: Set<String> = [word.lowercased()]
        return words.filter { seen.insert($0.lowercased()).inserted }
    }

    static func matchCase(_ word: String, like model: String) -> String {
        guard let first = model.first, first.isUppercase else { return word }
        return word.prefix(1).uppercased() + word.dropFirst()
    }
}

/// En sætning delt i ord og det, der står mellem dem. `separators` har altid ét element mere end `words`.
struct Tokens {
    var words: [String] = []
    var separators: [String] = []

    init(_ text: String) {
        var current = ""
        var inWord = false
        var separator = ""
        for character in text {
            let isWordCharacter = character.isLetter || character.isNumber
                || (inWord && (character == "-" || character == "'"))
            if isWordCharacter {
                if !inWord { separators.append(separator); separator = ""; inWord = true }
                current.append(character)
            } else {
                if inWord { words.append(current); current = ""; inWord = false }
                separator.append(character)
            }
        }
        if inWord { words.append(current) } else { separators.append(separator); return }
        separators.append("")
    }
}

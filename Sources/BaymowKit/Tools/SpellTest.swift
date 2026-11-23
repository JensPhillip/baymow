import Foundation
import BaymowCore

/// Stavetesten (AP-63): `--spell-test <sætninger.tsv> <resultat.json>`.
///
/// Hver linje er "skrevet tekst<TAB>facit". Testen måler både modellens rå svar og det, vagten lader igennem:
/// rettede fejl, fejl, der er markeret "tjek selv", oversete fejl, og – vigtigst – rettelser, der gør teksten forkert
/// (ord, der hverken stod i teksten eller i facit). Kun egne testsætninger; aldrig brugerens tekst.
@MainActor
public enum SpellTest {
    struct Count {
        var errors = 0, fixed = 0, flagged = 0, wrong = 0, cleanChanged = 0, falseFlags = 0
    }

    /// `cloud`: "claude" eller "openai" måler internet-hjælpen (AP-64). Nøglen læses fra miljøvariablen
    /// `BAYMOW_TEST_KEY`, så den ikke står på kommandolinjen.
    public static func run(sentencesFile: String, outputFile: String, cloud: String? = nil, level: String? = nil) -> Int32 {
        let level = level.flatMap(SpellingLevel.init(rawValue:)) ?? .standard
        guard let content = try? String(contentsOfFile: sentencesFile, encoding: .utf8) else {
            print("Kan ikke læse \(sentencesFile)"); return 1
        }
        let cases = content.split(separator: "\n").filter { !$0.hasPrefix("#") && $0.contains("\t") }.map { line in
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            return (written: parts[0], key: parts[1])
        }
        var status = "\(AppleSpellingModel.status())"
        var corrector = AppleSpellingModel.makeCorrector(level: level)
        if let cloud {
            guard let provider = CloudProvider(rawValue: cloud),
                  let key = ProcessInfo.processInfo.environment["BAYMOW_TEST_KEY"], !key.isEmpty else {
                print("Brug --cloud claude|openai og sæt BAYMOW_TEST_KEY"); return 1
            }
            corrector = CloudSpellingCorrector(provider: provider, key: key, level: level)
            status = provider.model
        }
        print("Model: \(status) · niveau: \(level.rawValue)")
        let assistant = SpellingAssistant(corrector: corrector, checker: SystemWordChecker(), level: level)

        var raw = Count(), guarded = Count()
        var rows: [[String: Any]] = []
        var seconds = 0.0
        // Tegnsætning (AP-68): sætninger, der er helt som facit (med tegn og store bogstaver), og sætninger, hvor
        // tegnene mellem ordene er ændret.
        var exact = 0, punctuationChanged = 0, punctuationNeeded = 0, punctuationFixed = 0
        for item in cases {
            let started = Date()
            let result = runBlocking { await assistant.check(item.written) }
            let elapsed = Date().timeIntervalSince(started)
            seconds += elapsed
            let proposal = assistant.lastProposals.joined(separator: " ")

            let rawScore = score(written: item.written, key: item.key, output: proposal, segments: nil)
            let guardedScore = score(written: item.written, key: item.key, output: result.text, segments: result.segments)
            let marksOf = { (text: String) in Tokens(text).separators.map { $0.trimmingCharacters(in: .whitespaces) } }
            if result.text == item.key { exact += 1 }
            if marksOf(result.text) != marksOf(item.written) { punctuationChanged += 1 }
            if marksOf(item.key) != marksOf(item.written) || item.key.first?.isUppercase != item.written.first?.isUppercase {
                punctuationNeeded += 1
                if marksOf(result.text) == marksOf(item.key) && result.text.first?.isUppercase == item.key.first?.isUppercase {
                    punctuationFixed += 1
                }
            }
            add(rawScore, to: &raw)
            add(guardedScore, to: &guarded)
            let marks = result.segments.filter { $0.kind == .uncertain }.map { "\($0.original)?(\($0.suggestions.joined(separator: "/")))" }
            rows.append(["skrevet": item.written, "facit": item.key, "model": proposal, "baymow": result.text,
                         "tjek_selv": marks, "forkerte_ord": guardedScore.wrongWords, "model_forkerte_ord": rawScore.wrongWords])
            let sign = guardedScore.count.wrong > 0 ? "✗" : (result.text == item.key ? "✓" : "·")
            print("\(sign) \(String(format: "%.1fs", elapsed)) \(item.written)\n    model:  \(proposal)\n    baymow: \(result.text)\(marks.isEmpty ? "" : "   tjek selv: " + marks.joined(separator: ", "))")
        }

        func summary(_ c: Count) -> [String: Int] {
            ["fejl_i_alt": c.errors, "rettet": c.fixed, "markeret": c.flagged, "overset": c.errors - c.fixed - c.flagged,
             "forkerte_rettelser": c.wrong, "fejlfri_saetninger_aendret": c.cleanChanged, "falske_markeringer": c.falseFlags]
        }
        let clean = cases.filter { $0.written == $0.key }.count
        let report: [String: Any] = [
            "dato": ISO8601DateFormatter().string(from: Date()), "model": "\(status)", "saetninger": cases.count,
            "fejlfri_saetninger": clean, "sekunder_pr_saetning": (seconds / Double(max(cases.count, 1)) * 100).rounded() / 100,
            "kun_model": summary(raw), "med_vagt": summary(guarded), "detaljer": rows, "niveau": level.rawValue,
            "tegnsaetning": ["helt_som_facit": exact, "saetninger_med_tegnfejl": punctuationNeeded,
                             "tegnfejl_rettet": punctuationFixed, "tegn_aendret": punctuationChanged],
        ]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: outputFile))
        }
        print("\n\(cases.count) sætninger, heraf \(clean) fejlfri. \(String(format: "%.2f", seconds / Double(max(cases.count, 1)))) s pr. sætning.")
        print("Kun model: \(summary(raw))")
        print("Med vagt:  \(summary(guarded))")
        print("Tegnsætning: \(exact) helt som facit · \(punctuationFixed) af \(punctuationNeeded) sætninger med tegnfejl rettet · tegn ændret i \(punctuationChanged)")
        return 0
    }

    struct Score {
        var count = Count()
        var wrongWords: [String] = []
    }

    static func score(written: String, key: String, output: String, segments: [SpellingSegment]?) -> Score {
        let w = Tokens(written).words.map { $0.lowercased() }
        let k = Tokens(key).words.map { $0.lowercased() }
        let o = Tokens(output).words.map { $0.lowercased() }
        var score = Score()
        let needed = subtract(k, w) // ordene, der skal frem ved rettelsen
        score.count.errors = needed.count
        var remaining = o
        for word in needed {
            if let index = remaining.firstIndex(of: word) { score.count.fixed += 1; remaining.remove(at: index) }
        }
        score.wrongWords = o.filter { !k.contains($0) && !w.contains($0) }
        score.count.wrong = score.wrongWords.count
        if written == key, o != w { score.count.cleanChanged = 1 }
        if let segments {
            let errorWords = Set(subtract(w, k))
            let unfixed = needed.count - score.count.fixed
            let flaggedErrors = segments.filter { $0.kind == .uncertain && !$0.isChanged
                && errorWords.contains($0.original.lowercased()) }.count
            score.count.flagged = min(flaggedErrors, unfixed)
            score.count.falseFlags = segments.filter { $0.kind == .uncertain && !errorWords.contains($0.original.lowercased()) }.count
        }
        return score
    }

    static func subtract(_ a: [String], _ b: [String]) -> [String] {
        var rest = b
        return a.filter { word in
            if let index = rest.firstIndex(of: word) { rest.remove(at: index); return false }
            return true
        }
    }

    static func add(_ score: Score, to total: inout Count) {
        total.errors += score.count.errors
        total.fixed += score.count.fixed
        total.flagged += score.count.flagged
        total.wrong += score.count.wrong
        total.cleanChanged += score.count.cleanChanged
        total.falseFlags += score.count.falseFlags
    }

    /// Kører asynkront arbejde færdigt fra kommandolinjen uden at låse hovedtråden.
    static func runBlocking<T>(_ work: @escaping @MainActor () async -> T) -> T {
        var value: T?
        Task { @MainActor in value = await work() }
        while value == nil { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        return value!
    }
}

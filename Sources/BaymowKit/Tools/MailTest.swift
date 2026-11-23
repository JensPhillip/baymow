import Foundation
import BaymowCore

/// Mail-svarets måling (AP-71): `--mail-test <traade.json> <resultat.json> --cloud openai|claude`.
///
/// Egne, opdigtede mailtråde – aldrig brugerens mails. Testen tjekker: tal i svaret, der hverken står i stikordene eller
/// tråden (opdigtede fakta), ord, der ikke må stå (fx en ordre fra tråden), ord, der skal stå, felter i [klammer], og om
/// der står et navn til sidst, når signaturen allerede findes. Svarene skrives også ud, så et menneske kan læse dem.
@MainActor
public enum MailTest {
    struct Case: Decodable {
        let navn: String
        let stikord: String
        let signatur: String
        let traad: String
        let maa_ikke_indeholde: [String]
        let skal_indeholde: [String]
        let felter_forventet: Bool
        /// Forventes det, at modellen skriver en opfølgning (den nyeste mail er brugerens egen)?
        var opfoelgning: Bool? = nil
    }

    public static func run(casesFile: String, outputFile: String, cloud: String?) -> Int32 {
        guard let data = FileManager.default.contents(atPath: casesFile),
              let cases = try? JSONDecoder().decode([Case].self, from: data) else { print("Kan ikke læse \(casesFile)"); return 1 }
        guard let provider = cloud.flatMap(CloudProvider.init(rawValue:)),
              let key = ProcessInfo.processInfo.environment["BAYMOW_TEST_KEY"], !key.isEmpty else {
            print("Brug --cloud openai|claude og sæt BAYMOW_TEST_KEY"); return 1
        }
        let model = CloudSpellingCorrector(provider: provider, key: key)
        var rows: [[String: Any]] = []
        var passed = 0
        for item in cases {
            let whole = item.stikord + item.signatur + "\n" + item.traad
            let parts = MailThread.split(whole: whole, notes: item.stikord)
            let started = Date()
            let name = "Jens Phillip Magnussen"
            let followUp = MailThread.latestIsFromUser(thread: parts.thread, name: name)
            let answer = SpellTest.runBlocking {
                (try? await model.send(instructions: MailReplyPrompt.instructions(tone: MailReplySettings.standardTone,
                                                                                  hasSignature: parts.hasSignature,
                                                                                  name: name, followUp: followUp),
                                       prompt: MailReplyPrompt.prompt(notes: parts.notes, thread: parts.thread),
                                       maxTokens: 1200)) ?? ""
            }
            let parsed = MailReplyPrompt.parse(answer)
            let reply = MailReplyPrompt.clean(parsed.reply, hasSignature: parts.hasSignature, name: name)
            let seconds = Date().timeIntervalSince(started)
            var problems: [String] = []
            let source = (item.stikord + " " + item.traad).lowercased()
            let numbers = reply.split(whereSeparator: { !$0.isNumber }).map(String.init).filter { !$0.isEmpty }
            // Tal, der ikke stod nogen steder, er kun i orden, hvis de står som en antagelse.
            let invented = numbers.filter { !source.contains($0) && !parsed.assumptions.joined(separator: " ").contains($0) }
            if !invented.isEmpty { problems.append("tal, der ikke stod nogen steder: \(invented)") }
            for word in item.maa_ikke_indeholde where reply.lowercased().contains(word.lowercased()) && !(item.signatur.isEmpty && word == "Jens\n") {
                problems.append("må ikke stå: \(word)")
            }
            for word in item.skal_indeholde where !reply.lowercased().contains(word.lowercased()) { problems.append("mangler: \(word)") }
            let fields = MailReplyPrompt.placeholders(in: reply)
            if item.felter_forventet && fields.isEmpty { problems.append("ingen [felter], selv om der mangler svar") }
            if parts.hasSignature, reply.components(separatedBy: "\n").last?.contains("Jens") == true {
                problems.append("navn til sidst, selv om signaturen findes")
            }
            if reply.isEmpty { problems.append("intet svar") }
            if let expected = item.opfoelgning, expected != followUp { problems.append("opfølgning ikke genkendt") }
            if problems.isEmpty { passed += 1 }
            rows.append(["navn": item.navn, "svar": reply, "felter": fields, "antagelser": parsed.assumptions, "problemer": problems,
                         "sekunder": (seconds * 10).rounded() / 10])
            print("\(problems.isEmpty ? "✓" : "✗") \(item.navn) (\(String(format: "%.1f", seconds)) s)\n\(reply)\n\(parsed.assumptions.isEmpty ? "" : "   antagelser: " + parsed.assumptions.joined(separator: " | ") + "\n")\(problems.isEmpty ? "" : "   → " + problems.joined(separator: "; ") + "\n")")
        }
        print("\(passed) af \(cases.count) uden problemer · model: \(provider.model)")
        let report: [String: Any] = ["dato": ISO8601DateFormatter().string(from: Date()), "model": provider.model,
                                     "uden_problemer": passed, "traade": cases.count, "detaljer": rows]
        if let out = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? out.write(to: URL(fileURLWithPath: outputFile))
        }
        return 0
    }
}

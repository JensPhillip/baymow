import Foundation
import BaymowCore

/// `Baymow --soak-selftest <minutter> <sekunder mellem oplæsninger> <resultatmappe>` (AP-51): kører appens rigtige
/// dele (session, valgt stemme, log) i lang tid med en lydløs oplæsning med jævne mellemrum, og skriver hukommelse
/// pr. runde til `<resultatmappe>/soak.csv`. Teksterne indeholder spor-ordene i `markers`, så log og filer bagefter
/// kan gennemsøges for dem. Loggen skrives til `<resultatmappe>/log/`.
@MainActor
public enum SoakTest {
    /// Usædvanlige ord, der kun findes i testteksterne. Findes de i en log eller fil, er tekst sluppet ud.
    public static let markers = ["zebrafinkeflokken", "kartoffelsalatsfestivalen", "Hvedebrødsdagenes", "solsikkemarken"]

    public static func run(minutes: Double, interval: Double, outputDirectory: String) -> Int32 {
        let out = URL(fileURLWithPath: outputDirectory, isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let suite = "baymow.soak-selftest"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        let apple = AppleSpeechEngine()
        apple.volume = 0
        let catalog = VoiceCatalog(engines: [apple], settings: settings)
        let sessions = ReadingSessionManager(catalog: catalog, settings: settings,
                                             diagnostics: DiagnosticsService(directory: out.appendingPathComponent("log")))

        var csv = "tid,runde,stemme,hukommelse_mb,tilstand_under,frigivet\n"
        func save() { try? csv.write(to: out.appendingPathComponent("soak.csv"), atomically: true, encoding: .utf8) }
        func spin(_ seconds: TimeInterval, until done: () -> Bool = { false }) {
            let end = Date().addingTimeInterval(seconds)
            while !done(), Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.25)) }
        }

        let start = Date()
        var round = 0
        while Date().timeIntervalSince(start) < minutes * 60 {
            round += 1
            let roundStart = Date()
            let text = soakText(round: round)
            let notice = sessions.start(text: text, sourceAppName: "Soak", sourceBundleID: "dk.baymow.soak", triggeredAt: Date())
            spin(5)
            let stateDuring = notice == nil ? "\(sessions.state)" : "besked"
            // Læs til ende (højst 90 s), luk som brugeren ville gøre, og mål.
            spin(90) { sessions.state == .finished }
            sessions.close()
            spin(2)
            let voice = catalog.voice(for: .danish)?.name ?? "ingen"
            csv += String(format: "%.0f,%d,%@,%.1f,%@,%@\n", Date().timeIntervalSince(start), round, voice,
                          MemorySelfTest.footprintMB(), stateDuring, sessions.hasSession ? "nej" : "ja")
            save()
            spin(max(0, interval - Date().timeIntervalSince(roundStart)))
        }
        save()
        return 0
    }

    /// Almindelig dansk tekst med spor-ord, tal og forkortelser, så tekstforberedelsen også bruges.
    static func soakText(round: Int) -> String {
        let marker = markers[round % markers.count]
        return "Runde \(round): I dag gik vi en tur forbi \(marker), hvor der var ca. 250 mennesker kl. 14.30. "
            + "Bagefter drak vi kaffe og talte om, hvordan man læser en lang tekst højt i et roligt tempo. "
            + "Det tog bl.a. 20 minutter at finde hjem igen, fordi vejen var spærret pga. et vejarbejde."
    }
}

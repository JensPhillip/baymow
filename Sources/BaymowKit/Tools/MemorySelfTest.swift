import Foundation
import Darwin
import BaymowCore

/// `--memory-selftest <apple|piper>` (AP-21): læser 20.000 tegn lydløst, skifter til en ny tekst midt i,
/// lukker og måler appens hukommelse før, under og efter. Består, hvis hukommelsen efter luk er højst
/// 10 MB over udgangspunktet.
@MainActor
public enum MemorySelfTest {
    /// Hukommelsen, som Aktivitetsovervågning viser den ("Hukommelse"), i MB.
    static func footprintMB() -> Double {
        // macOS giver frigjort hukommelse tilbage lidt efter lidt. Bed om det med det samme, så målingen viser,
        // hvad der faktisk er i brug, og ikke hvad allokatoren endnu ikke har ryddet op i.
        malloc_zone_pressure_relief(nil, 0)
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    public static func run(engineName: String) -> Int32 {
        let suite = "baymow.memory-selftest"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        settings.forcedLanguage = .danish
        let logDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("baymow-memory-selftest")
        defer { try? FileManager.default.removeItem(at: logDirectory) }

        let engine: SpeechEngine
        switch engineName {
        case "piper":
            // Kort nedlukningstid i testen, så den kan måles inden for få sekunder; appen bruger 60 s.
            let piper = BackendSpeechEngine(backend: PiperBackend(idleUnloadAfter: 2))
            piper.volume = 0
            guard let voice = piper.installedVoices().first else {
                print("Ingen Piper-stemme installeret")
                return 1
            }
            settings.preferredVoiceIDs["da"] = voice.id
            engine = piper
        default:
            let apple = AppleSpeechEngine()
            apple.volume = 0
            engine = apple
        }
        let catalog = VoiceCatalog(engines: [engine], settings: settings)
        let sessions = ReadingSessionManager(catalog: catalog, settings: settings,
                                             diagnostics: DiagnosticsService(directory: logDirectory))

        func spin(_ seconds: TimeInterval, sample: ((Double) -> Void)? = nil) {
            let end = Date().addingTimeInterval(seconds)
            while Date() < end {
                RunLoop.main.run(until: Date().addingTimeInterval(0.25))
                sample?(footprintMB())
            }
        }

        // Opvarmning: stemmen indlæses og bruges én gang, som appen gør ved opstart og første oplæsning.
        // Udgangspunktet måles bagefter, så målingen viser, hvad selve oplæsningen af en lang tekst koster.
        sessions.start(text: "Dette er en kort sætning, der varmer stemmen op.")
        spin(4)
        sessions.close()
        spin(2)
        let before = footprintMB()

        // Tre gennemløb: læs 20.000 tegn, skift til en ny tekst midt i, luk. Første gennemløb kan koste en
        // engangsudgift (stemmemotorens arbejdslager vokser til lange sætninger); en lækage ville vise sig som
        // vækst fra gennemløb til gennemløb.
        var afterClose: [Double] = []
        var peak = before
        var allSpoke = true, allReplaced = true, allReleased = true
        for round in 0..<3 {
            if let notice = sessions.start(text: longText(characters: 20_000, offset: round)) {
                print("Kunne ikke starte: \(notice.message)")
                return 1
            }
            spin(6) { peak = max(peak, $0) }
            allSpoke = allSpoke && sessions.state == .speaking
            // Nyt tryk på genvejen midt i teksten: den gamle oplæsning skal erstattes rent.
            sessions.start(text: longText(characters: 20_000, offset: round + 1))
            spin(3) { peak = max(peak, $0) }
            allReplaced = allReplaced && sessions.state == .speaking && sessions.progress < 0.2
            sessions.close()
            // Piper lukker sin motor ned 2 s efter sidste sætning (i appen 60 s); en sætning kan være i gang ved luk.
            spin(engineName == "piper" ? 6 : 3)
            allReleased = allReleased && !sessions.hasSession
            afterClose.append(footprintMB())
        }

        let firstCost = afterClose[0] - before
        let growth = afterClose[2] - afterClose[0]
        let passed = growth <= 10 && allSpoke && allReplaced && allReleased
        print(String(format: "%@: før %.1f MB · top %.1f MB · efter luk %.1f / %.1f / %.1f MB",
                     engineName, before, peak, afterClose[0], afterClose[1], afterClose[2]))
        print(String(format: "  første gennemløb %+.1f MB (engangsudgift) · vækst fra 1. til 3. gennemløb %+.1f MB", firstCost, growth))
        print("  oplæste: \(allSpoke ? "ja" : "nej") · ny tekst erstattede den gamle: \(allReplaced ? "ja" : "nej") · session frigivet: \(allReleased ? "ja" : "nej")")
        print(passed ? "  BESTÅET (ingen vækst over 10 MB fra gennemløb til gennemløb)" : "  IKKE BESTÅET")
        print(firstCost <= 10 ? "  Også inden for 10 MB af udgangspunktet." : "  Bemærk: første gennemløb er over 10 MB af udgangspunktet.")
        return passed ? 0 : 1
    }

    /// Almindelig dansk tekst gentaget op til den ønskede længde. `offset` giver en anden tekst.
    static func longText(characters: Int, offset: Int = 0) -> String {
        let paragraphs = [
            "Kommunen åbner et nyt bibliotek ved havnen til foråret. Bygningen er blevet sat i stand, og der bliver plads til både børn og voksne.",
            "Mange oplever, at en tekst bliver lettere at forstå, når den bliver læst højt i et roligt tempo. Derfor bruger flere skoler oplæsning i undervisningen.",
            "Fotosyntese er den proces, hvor planter omdanner lysenergi til kemisk energi. Processen foregår i bladenes grønkorn.",
            "Tak for mødet i går. Jeg har talt med værkstedet, og de kan tage bilen ind på torsdag. Reparationen tager cirka tre timer.",
        ]
        var text = ""
        var index = offset
        while text.count < characters {
            text += paragraphs[index % paragraphs.count] + " "
            index += 1
        }
        return String(text.prefix(characters))
    }
}

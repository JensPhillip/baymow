import Foundation
import Combine
import BaymowCore

/// `Baymow --highlight-selftest` (I1): læser en dansk tekst lydløst med Apples stemme og den rigtige session og
/// kontrollerer, at fremhævningen følger ordene i rækkefølge – også når tal siges som ord.
@MainActor
public enum HighlightSelfTest {
    public static func run() -> Int32 {
        let suite = "baymow.highlight-selftest"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        settings.forcedLanguage = .danish
        settings.showReadingWindow = true
        let apple = AppleSpeechEngine()
        apple.volume = 0
        let catalog = VoiceCatalog(engines: [apple], settings: settings)
        let logs = FileManager.default.temporaryDirectory.appendingPathComponent("baymow-highlight-selftest")
        defer { try? FileManager.default.removeItem(at: logs) }
        let sessions = ReadingSessionManager(catalog: catalog, settings: settings, diagnostics: DiagnosticsService(directory: logs))

        let text = "Mødet er flyttet til torsdag kl. 14.30 i det store lokale. Husk at tage kaffe med."
        var seen: [NSRange] = []
        let watcher = sessions.$highlightRange.sink { if let range = $0, seen.last != range { seen.append(range) } }
        defer { watcher.cancel() }

        sessions.start(text: text)
        let end = Date().addingTimeInterval(30)
        while sessions.state != .finished, Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }

        let shown = text as NSString
        let words = seen.map { shown.substring(with: $0) }
        let inOrder = zip(seen, seen.dropFirst()).allSatisfy { $0.location <= $1.location }
        var failures = 0
        func check(_ name: String, _ ok: Bool) {
            print("  \(ok ? "ok  " : "FEJL") \(name)")
            if !ok { failures += 1 }
        }
        print("  info: \(words.count) fremhævninger: \(words.joined(separator: " | "))")
        check("oplæsningen blev færdig", sessions.state == .finished)
        check("første fremhævning er første ord", words.first == "Mødet")
        check("fremhævningen går fremad i teksten", inOrder)
        check("\"kl. 14.30\" fremhæves, når tallet siges", words.contains("kl. 14.30"))
        check("sidste ord fremhæves", words.last == "med")
        check("intet fremhæves, når oplæsningen er færdig", sessions.highlightRange == nil)
        print(failures == 0 ? "Fremhævningen bestod" : "Fremhævningen fejlede i \(failures) punkt(er)")
        return failures == 0 ? 0 : 1
    }
}

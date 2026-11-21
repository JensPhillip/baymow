import AppKit
import ApplicationServices
import BaymowCore

/// `open -n -W build/Baymow.app --args --inplace-selftest` (I1): åbner en testtekst i TextEdit, markerer den via
/// Tilgængelighed, henter den som genvejen gør, og kontrollerer, at ankeret giver en skærmplacering for hvert ord i
/// rigtig rækkefølge. Springer over, hvis TextEdit allerede kører (brugerens dokumenter røres ikke). Lukker TextEdit
/// bagefter. Resultat i ~/Library/Logs/Baymow/inplace-selftest.txt (kun tal og ja/nej – testteksten er vores egen).
@MainActor
public enum InPlaceSelfTest {
    public static func run() -> Int32 {
        var lines: [String] = []
        defer {
            let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/Baymow")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? lines.joined(separator: "\n").write(to: dir.appendingPathComponent("inplace-selftest.txt"), atomically: true, encoding: .utf8)
        }
        let bundleID = "com.apple.TextEdit"
        // Kører TextEdit allerede, åbnes testteksten i sit eget vindue, og kun det vindue lukkes bagefter.
        let wasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()

        let text = "Mødet er flyttet til torsdag kl. 14.30 i det store lokale.\nHusk at tage kaffe med til alle."
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("baymow-inplace-selftest.txt")
        try? text.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        guard let editor = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            lines.append("FEJL: TextEdit findes ikke"); return 1
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        var launched: NSRunningApplication?
        NSWorkspace.shared.open([file], withApplicationAt: editor, configuration: configuration) { app, _ in launched = app }
        func spin(_ seconds: TimeInterval, until done: () -> Bool) {
            let end = Date().addingTimeInterval(seconds)
            while !done(), Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        }
        var testWindow: AXUIElement?
        defer {
            if wasRunning {
                // Luk kun testvinduet (dokumentet er uændret, så der spørges ikke om at gemme).
                var button: CFTypeRef?
                if let testWindow, AXUIElementCopyAttributeValue(testWindow, kAXCloseButtonAttribute as CFString, &button) == .success,
                   let button, CFGetTypeID(button) == AXUIElementGetTypeID() {
                    AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
                }
            } else {
                launched?.terminate()
            }
        }

        // Vent på, at TextEdit er forrest, og at tekstfeltet med vores tekst har fokus.
        var field: AXUIElement?
        spin(10) {
            guard let pid = launched?.processIdentifier,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return false }
            var focused: CFTypeRef?
            guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute as CFString,
                                                &focused) == .success, let focused,
                  CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
            var value: CFTypeRef?
            AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXValueAttribute as CFString, &value)
            guard (value as? String)?.hasPrefix("Mødet") == true else { return false }
            field = (focused as! AXUIElement)
            return true
        }
        guard let field else { lines.append("FEJL: TextEdits tekstfelt blev ikke fundet"); return 1 }
        var window: CFTypeRef?
        if AXUIElementCopyAttributeValue(field, kAXWindowAttribute as CFString, &window) == .success, let window,
           CFGetTypeID(window) == AXUIElementGetTypeID() {
            testWindow = (window as! AXUIElement)
        }
        lines.append("info: TextEdit kørte \(wasRunning ? "allerede – kun testvinduet lukkes" : "ikke – lukkes bagefter")")

        var whole = CFRange(location: 0, length: (text as NSString).length)
        let selection = AXValueCreate(.cfRange, &whole)!
        AXUIElementSetAttributeValue(field, kAXSelectedTextRangeAttribute as CFString, selection)
        spin(0.5) { false }

        var captured: Result<CapturedText, CaptureFailure>?
        Task { captured = await TextCaptureService().capture() }
        spin(5) { captured != nil }

        var failures = 0
        func check(_ name: String, _ ok: Bool) {
            lines.append("\(ok ? "ok  " : "FEJL") \(name)")
            if !ok { failures += 1 }
        }
        guard case .success(let result)? = captured else {
            check("teksten blev hentet", false)
            return 1
        }
        check("teksten blev hentet med Tilgængelighed", result.method == .accessibility)
        check("den hentede tekst er testteksten", result.text == text)
        check("markeringens placering er kendt (anker)", result.anchor != nil)
        guard let anchor = result.anchor else { return 1 }

        let wordRegex = try! NSRegularExpression(pattern: #"[\p{L}\p{N}]+"#)
        let words = wordRegex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)).map(\.range)
        let rects = words.map { anchor.screenRect(forSelectedRange: $0) }
        let found = rects.compactMap { $0 }
        lines.append("info: \(found.count) af \(words.count) ord har en skærmplacering")
        check("alle ord har en skærmplacering", found.count == words.count)
        let breakIndex = words.firstIndex { $0.location > (text as NSString).range(of: "\n").location } ?? words.count
        let firstLine = Array(found.prefix(breakIndex))
        check("ordene på første linje står fra venstre mod højre",
              zip(firstLine, firstLine.dropFirst()).allSatisfy { $0.minX < $1.minX })
        if let lastOnFirst = firstLine.last, breakIndex < found.count {
            check("anden linje står under første", found[breakIndex].minY > lastOnFirst.minY)
        }
        // Hele vejen, som genvejen gør: start oplæsningen (lydløst) med fremhævning i teksten slået til, og mål, om det
        // gule felt vises oven på ordene.
        let suite = "baymow.inplace-selftest"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        settings.forcedLanguage = .danish
        settings.highlightInPlace = true
        let apple = AppleSpeechEngine()
        apple.volume = 0
        let catalog = VoiceCatalog(engines: [apple], settings: settings)
        let logs = FileManager.default.temporaryDirectory.appendingPathComponent("baymow-inplace-selftest")
        defer { try? FileManager.default.removeItem(at: logs) }
        let sessions = ReadingSessionManager(catalog: catalog, settings: settings, diagnostics: DiagnosticsService(directory: logs))
        let highlighter = InPlaceHighlighter(sessions: sessions, settings: settings)
        // Samme rækkefølge som AppShell.
        sessions.start(text: result.text)
        highlighter.begin(captured: result.text, anchor: anchor)

        let wordRects = found.map { InPlaceHighlighter.appKitRect(fromQuartz: $0).insetBy(dx: -4, dy: -4) }
        var frames: [CGRect] = []
        let end = Date().addingTimeInterval(30)
        while sessions.state != .finished, Date() < end {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            if let frame = highlighter.overlayFrame, frames.last != frame { frames.append(frame) }
        }
        let onWords = frames.filter { frame in wordRects.contains { $0.intersects(frame) } }
        lines.append("info: det gule felt blev vist \(frames.count) steder, heraf \(onWords.count) oven på et ord")
        check("oplæsningen blev færdig", sessions.state == .finished)
        check("det gule felt blev vist under oplæsningen (mindst 10 placeringer)", frames.count >= 10)
        check("det gule felt sad oven på ordene hver gang", !frames.isEmpty && onWords.count == frames.count)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        check("det gule felt er væk, når oplæsningen er færdig", highlighter.overlayFrame == nil)

        lines.append(failures == 0 ? "BESTÅET" : "IKKE BESTÅET")
        return failures == 0 ? 0 : 1
    }
}

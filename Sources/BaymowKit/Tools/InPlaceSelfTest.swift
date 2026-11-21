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
        guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else {
            lines.append("SPRUNGET OVER: TextEdit kører allerede")
            return 2
        }
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
        defer { launched?.terminate() }

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
        lines.append(failures == 0 ? "BESTÅET" : "IKKE BESTÅET")
        return failures == 0 ? 0 : 1
    }
}

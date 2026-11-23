import AppKit
import ApplicationServices
import BaymowCore

/// Prøve til idé I15 (mail-svar): kan Baymow læse svarfeltet med den citerede tråd i et mailprogram, og kan den sætte
/// et svar ind øverst uden at røre tråden?
///
/// Rapporten indeholder kun roller, længder, antal og ja/nej – aldrig mailens tekst. Den skrives til
/// `~/Library/Logs/Baymow/mail-probe.txt` (én blok pr. kørsel). Køres med
/// `open -n Baymow.app --args --mail-probe`; brugeren har så 15 sekunder (eller tallet efter `--mail-probe`) til at klikke i svarfeltet. Et bip, når den
/// starter, og to, når den har målt.
@MainActor
public enum MailProbe {
    public static func run(delay: Double = 15) {
        NSSound.beep()
        Thread.sleep(forTimeInterval: delay)
        var lines: [String] = ["== \(ISO8601DateFormatter().string(from: Date()))", "trusted: \(AXIsProcessTrusted())"]
        defer {
            let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/Baymow")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent("mail-probe.txt")
            let block = lines.joined(separator: "\n") + "\n\n"
            if let handle = try? FileHandle(forWritingTo: file) {
                handle.seekToEndOfFile(); handle.write(Data(block.utf8)); try? handle.close()
            } else {
                try? block.write(to: file, atomically: true, encoding: .utf8)
            }
            NSSound.beep(); Thread.sleep(forTimeInterval: 0.3); NSSound.beep()
        }

        guard let app = NSWorkspace.shared.frontmostApplication else { lines.append("intet program forrest"); return }
        lines.append("program: \(app.bundleIdentifier ?? "–")")
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 2.0)
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        var ref: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &ref)
        guard err == .success, let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else {
            lines.append("fokuseret element: fejl \(err.rawValue)"); return
        }
        let focused = ref as! AXUIElement
        lines.append("fokuseret: \(role(focused))")

        // 1. Kan hele feltet læses (dine ord + den citerede tråd)?
        let value = copy(focused, kAXValueAttribute) as? String
        let count = copy(focused, kAXNumberOfCharactersAttribute) as? Int
        lines.append("AXValue: \(value.map { "\($0.count) tegn, \($0.components(separatedBy: .newlines).count) linjer" } ?? "kan ikke læses")")
        lines.append("AXNumberOfCharacters: \(count.map(String.init) ?? "–")")
        var range = CFRange(location: 0, length: 0)
        if let selected = copy(focused, kAXSelectedTextRangeAttribute), CFGetTypeID(selected) == AXValueGetTypeID() {
            AXValueGetValue(selected as! AXValue, .cfRange, &range)
            lines.append("markør/markering: position \(range.location), længde \(range.length)")
        } else {
            lines.append("markør/markering: kan ikke læses")
        }

        // 2. Kan grænsen mellem dit udkast og tråden findes? (kun ja/nej og en position)
        if let value {
            let markers = ["skrev:", "wrote:", "Fra:", "From:", "Sendt:", "Sent:", "-----Original"]
            let lineList = value.components(separatedBy: .newlines)
            let quoteLines = lineList.filter { $0.hasPrefix(">") }.count
            let boundary = lineList.firstIndex { line in
                (line.contains("skrev:") || line.contains("wrote:")) || line.hasPrefix("Fra:") || line.hasPrefix("From:")
                    || line.hasPrefix("-----Original")
            }
            lines.append("linjer, der starter med '>': \(quoteLines)")
            lines.append("citat-overskrift fundet: \(boundary.map { "ja, linje \($0 + 1) af \(lineList.count)" } ?? "nej")")
            lines.append("kendte markører i teksten: \(markers.filter { value.contains($0) }.count) af \(markers.count)")
        }

        // 3. Kan Baymow sætte en markering og skrive tekst (til at erstatte udkastet uden at røre tråden)?
        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(focused, kAXSelectedTextRangeAttribute as CFString, &settable)
        lines.append("markering kan sættes: \(settable.boolValue)")
        settable = false
        AXUIElementIsAttributeSettable(focused, kAXSelectedTextAttribute as CFString, &settable)
        lines.append("markeret tekst kan skrives: \(settable.boolValue)")
        settable = false
        AXUIElementIsAttributeSettable(focused, kAXValueAttribute as CFString, &settable)
        lines.append("hele værdien kan skrives: \(settable.boolValue)")

        // 5. Webfelter (Apple Mail, browsere): hele teksten via tekstmarkører.
        if let start = copy(focused, "AXStartTextMarker"), let end = copy(focused, "AXEndTextMarker") {
            var markerRange: CFTypeRef?
            let pair = [start, end] as CFArray
            AXUIElementCopyParameterizedAttributeValue(focused, "AXTextMarkerRangeForUnorderedTextMarkers" as CFString, pair, &markerRange)
            var whole: CFTypeRef?
            if let markerRange {
                AXUIElementCopyParameterizedAttributeValue(focused, "AXStringForTextMarkerRange" as CFString, markerRange, &whole)
            }
            lines.append("hele feltet via tekstmarkører: \((whole as? String).map { describeText($0) } ?? "kan ikke læses")")
        } else {
            lines.append("hele feltet via tekstmarkører: ingen markører")
        }
        if let marker = copy(focused, "AXSelectedTextMarkerRange") {
            var before: CFTypeRef?
            if let start = copy(focused, "AXStartTextMarker") {
                var startOfSelection: CFTypeRef?
                AXUIElementCopyParameterizedAttributeValue(focused, "AXStartTextMarkerForTextMarkerRange" as CFString, marker, &startOfSelection)
                if let startOfSelection {
                    var range: CFTypeRef?
                    AXUIElementCopyParameterizedAttributeValue(focused, "AXTextMarkerRangeForUnorderedTextMarkers" as CFString,
                                                               [start, startOfSelection] as CFArray, &range)
                    if let range {
                        AXUIElementCopyParameterizedAttributeValue(focused, "AXStringForTextMarkerRange" as CFString, range, &before)
                    }
                }
            }
            lines.append("markørens position (tegn før markøren): \((before as? String)?.count.description ?? "kan ikke læses")")
        }

        // 7. Hvilke tekst-funktioner har feltet? (kun navne)
        var parameterized: CFArray?
        AXUIElementCopyParameterizedAttributeNames(focused, &parameterized)
        let names = (parameterized as? [String]) ?? []
        lines.append("tekst-funktioner: \(names.filter { $0.contains("Marker") || $0.contains("Index") }.sorted().joined(separator: ", "))")

        func text(_ from: CFTypeRef, _ to: CFTypeRef) -> String? {
            var range: CFTypeRef?
            AXUIElementCopyParameterizedAttributeValue(focused, "AXTextMarkerRangeForUnorderedTextMarkers" as CFString,
                                                       [from, to] as CFArray, &range)
            guard let range else { return nil }
            var value: CFTypeRef?
            AXUIElementCopyParameterizedAttributeValue(focused, "AXStringForTextMarkerRange" as CFString, range, &value)
            return value as? String
        }
        func marker(_ index: Int) -> CFTypeRef? {
            var value: CFTypeRef?
            AXUIElementCopyParameterizedAttributeValue(focused, "AXTextMarkerForIndex" as CFString, index as CFNumber, &value)
            return value
        }

        // 8. Markørens position: teksten fra starten til markøren.
        if let start = copy(focused, "AXStartTextMarker"), let selection = copy(focused, "AXSelectedTextMarkerRange") {
            for name in ["AXStartTextMarkerForTextMarkerRange", "AXTextMarkerRangeStart"] {
                var caret: CFTypeRef?
                let err = AXUIElementCopyParameterizedAttributeValue(focused, name as CFString, selection, &caret)
                lines.append("markør via \(name): \(err == .success ? (caret.flatMap { text(start, $0) }.map { "\($0.utf16.count) tegn før markøren" } ?? "ingen tekst") : "fejl \(err.rawValue)")")
            }
            var index: CFTypeRef?
            let err = AXUIElementCopyParameterizedAttributeValue(focused, "AXIndexForTextMarker" as CFString, selection, &index)
            lines.append("markør via AXIndexForTextMarker(markering): \(err == .success ? "\(index as? Int ?? -1)" : "fejl \(err.rawValue)")")
        }

        // 9. Markér præcis brugerens del: find positionen trin for trin (halvering), så teksten passer.
        if let start = copy(focused, "AXStartTextMarker"), let end = copy(focused, "AXEndTextMarker"),
           let whole = text(start, end),
           let header = whole.components(separatedBy: .newlines).firstIndex(where: {
               $0.contains("skrev:") || $0.contains("wrote:") || $0.hasPrefix("Fra:") || $0.hasPrefix("From:") }) {
            let target = whole.components(separatedBy: .newlines)[..<header].joined(separator: "\n").utf16.count
            var low = 0, high = target * 2 + 50, steps = 0
            while low < high, steps < 30 {
                let middle = (low + high) / 2
                let length = marker(middle).flatMap { text(start, $0) }?.utf16.count ?? Int.max
                if length < target { low = middle + 1 } else { high = middle }
                steps += 1
            }
            let found = marker(low).flatMap { text(start, $0) }?.utf16.count
            lines.append("halvering: indeks \(low) giver \(found.map(String.init) ?? "?") af \(target) tegn efter \(steps) trin")
            if let m = marker(low) {
                var part: CFTypeRef?
                AXUIElementCopyParameterizedAttributeValue(focused, "AXTextMarkerRangeForUnorderedTextMarkers" as CFString,
                                                           [start, m] as CFArray, &part)
                if let part {
                    let setErr = AXUIElementSetAttributeValue(focused, "AXSelectedTextMarkerRange" as CFString, part)
                    Thread.sleep(forTimeInterval: 0.3)
                    var selectedText: CFTypeRef?
                    if let selected = copy(focused, "AXSelectedTextMarkerRange") {
                        AXUIElementCopyParameterizedAttributeValue(focused, "AXStringForTextMarkerRange" as CFString, selected, &selectedText)
                    }
                    let got = (selectedText as? String)?.utf16.count
                    lines.append("markér kun dine ord: sæt=\(setErr.rawValue), markeret \(got.map(String.init) ?? "?") af \(target) tegn\(got == target ? " ✓" : "")")
                }
            }
        }

        // 10. ⇧⌘↑ fra markøren: markerer brugerens stikord (alt over markøren). Kopiér, og mål længden; → fjerner
        // markeringen igen, så markøren står, hvor den stod.
        do {
            let pasteboard = NSPasteboard.general
            let saved = (pasteboard.pasteboardItems ?? []).map { item in
                item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
            }
            // Markørens position først (via skærmplacering → tekstmarkør → indeks).
            if let selection = copy(focused, "AXSelectedTextMarkerRange") {
                var bounds: CFTypeRef?
                AXUIElementCopyParameterizedAttributeValue(focused, "AXBoundsForTextMarkerRange" as CFString, selection, &bounds)
                var rect = CGRect.zero
                if let bounds, CFGetTypeID(bounds) == AXValueGetTypeID() { AXValueGetValue(bounds as! AXValue, .cgRect, &rect) }
                var point = CGPoint(x: rect.minX + 1, y: rect.midY)
                var marker: CFTypeRef?
                if let pointValue = AXValueCreate(.cgPoint, &point) {
                    AXUIElementCopyParameterizedAttributeValue(focused, "AXTextMarkerForPosition" as CFString, pointValue, &marker)
                }
                var index: CFTypeRef?
                if let marker { AXUIElementCopyParameterizedAttributeValue(focused, "AXIndexForTextMarker" as CFString, marker, &index) }
                lines.append("markør via skærmplacering: \(rect == .zero ? "ingen placering" : "indeks \((index as? Int).map(String.init) ?? "?")")")
            }
            let before = pasteboard.changeCount
            let source = CGEventSource(stateID: .privateState)
            for (key, flags) in [(CGKeyCode(0x7E), CGEventFlags([.maskCommand, .maskShift]))] {
                let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
                let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
                down?.flags = flags; up?.flags = flags
                down?.post(tap: .cgSessionEventTap); up?.post(tap: .cgSessionEventTap)
            }
            Thread.sleep(forTimeInterval: 0.2)
            press(SelectionReplacer.keyCode(for: "c"))
            var waited = 0.0
            while pasteboard.changeCount == before, waited < 1.0 { Thread.sleep(forTimeInterval: 0.05); waited += 0.05 }
            let stikord = pasteboard.changeCount != before ? pasteboard.string(forType: .string) : nil
            lines.append("⇧⌘↑ + kopiér: \(stikord.map { "\($0.count) tegn, \($0.components(separatedBy: .newlines).count) linjer, citat-overskrift med: \($0.contains("skrev:") || $0.contains("wrote:") ? "ja (for meget)" : "nej")" } ?? "intet kopieret")")
            // → fjerner markeringen; markøren ender i slutningen af markeringen (der, hvor den stod).
            let right = CGEvent(keyboardEventSource: source, virtualKey: 0x7C, keyDown: true)
            let rightUp = CGEvent(keyboardEventSource: source, virtualKey: 0x7C, keyDown: false)
            right?.post(tap: .cgSessionEventTap); rightUp?.post(tap: .cgSessionEventTap)
            Thread.sleep(forTimeInterval: 0.2)
            pasteboard.clearContents()
            pasteboard.writeObjects(saved.map { entries -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in entries { item.setData(data, forType: type) }
                return item
            })
        }

        // 6. "Markér alt + Kopiér" i feltet. Markøren sættes øverst bagefter, og udklipsholderen lægges tilbage.
        let pasteboard = NSPasteboard.general
        let saved = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        let changeBefore = pasteboard.changeCount
        press(SelectionReplacer.keyCode(for: "a"))
        Thread.sleep(forTimeInterval: 0.15)
        press(SelectionReplacer.keyCode(for: "c"))
        var waited = 0.0
        while pasteboard.changeCount == changeBefore, waited < 1.0 { Thread.sleep(forTimeInterval: 0.05); waited += 0.05 }
        if pasteboard.changeCount != changeBefore {
            let types = (pasteboard.types ?? []).map(\.rawValue)
            lines.append("kopi: typer \(types.filter { ["public.rtf", "public.html", "public.utf8-plain-text", "com.apple.webarchive"].contains($0) })")
            lines.append("kopi som tekst: \(pasteboard.string(forType: .string).map { describeText($0) } ?? "ingen")")
            if let rtf = pasteboard.data(forType: .rtf) {
                let visible = RTFText.read(Array(rtf))
                lines.append("kopi som RTF: \(describeText(String(utf16CodeUnits: visible.text, count: visible.text.count)))")
            }
        } else {
            lines.append("kopi: intet blev kopieret")
        }
        press(0x7E) // pil op med ⌘: markøren øverst, markeringen væk
        Thread.sleep(forTimeInterval: 0.2)
        pasteboard.clearContents()
        pasteboard.writeObjects(saved.map { entries -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entries { item.setData(data, forType: type) }
            return item
        })

        // 4. Hvordan ser trådens opbygning ud i webområdet (Apple Mail og browsere)? Kun roller og antal.
        var element: AXUIElement? = focused
        var depth = 0
        while let current = element, depth < 6 {
            if (copy(current, kAXRoleAttribute) as? String) == "AXWebArea" { break }
            element = copy(current, kAXParentAttribute).flatMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
            depth += 1
        }
        let root = element ?? focused
        var histogram: [String: Int] = [:]
        var queue = [root], visited = 0
        var quoteGroups = 0
        while !queue.isEmpty, visited < 3000 {
            let node = queue.removeFirst()
            visited += 1
            let r = role(node)
            histogram[r, default: 0] += 1
            let description = (copy(node, kAXRoleDescriptionAttribute) as? String ?? "").lowercased()
            if description.contains("quote") || description.contains("citat") { quoteGroups += 1 }
            if let children = copy(node, kAXChildrenAttribute) as? [AXUIElement] { queue += children }
        }
        lines.append("elementer i feltet: \(visited)\(visited >= 3000 ? " (stoppet)" : "")")
        lines.append("citatblokke (blockquote): \(quoteGroups)")
        lines.append("roller: " + histogram.sorted { $0.value > $1.value }.prefix(12).map { "\($0.key)×\($0.value)" }.joined(separator: ", "))
    }

    /// Kun længde, linjer og om/hvor citatet begynder – aldrig selve teksten.
    private static func describeText(_ text: String) -> String {
        let list = text.components(separatedBy: .newlines)
        let boundary = list.firstIndex { line in
            line.contains("skrev:") || line.contains("wrote:") || line.hasPrefix("Fra:") || line.hasPrefix("From:")
                || line.hasPrefix("-----Original")
        }
        let charsBefore = boundary.map { list[..<$0].joined(separator: "\n").count }
        return "\(text.count) tegn, \(list.count) linjer, citat-overskrift \(boundary.map { "på linje \($0 + 1) (\(charsBefore ?? 0) tegn før)" } ?? "ikke fundet")"
    }

    /// ⌘ + en tast i det forreste program.
    private static func press(_ key: CGKeyCode) {
        let source = CGEventSource(stateID: .privateState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }

    private static func role(_ element: AXUIElement) -> String {
        "\(copy(element, kAXRoleAttribute) as? String ?? "–")/\(copy(element, kAXSubroleAttribute) as? String ?? "–")"
    }
}

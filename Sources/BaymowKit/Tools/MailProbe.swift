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

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }

    private static func role(_ element: AXUIElement) -> String {
        "\(copy(element, kAXRoleAttribute) as? String ?? "–")/\(copy(element, kAXSubroleAttribute) as? String ?? "–")"
    }
}

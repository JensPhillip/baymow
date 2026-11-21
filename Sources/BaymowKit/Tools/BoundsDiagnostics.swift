import AppKit
import ApplicationServices
import BaymowCore

/// `open -n -W build/Baymow.app --args --ax-bounds <bundle-id>` (I1): undersøger, hvordan et program oplyser, hvor
/// tekst står på skærmen. Skriver kun attributnavne, fejlkoder og rektangelstørrelser – aldrig tekst – til
/// ~/Library/Logs/Baymow/ax-bounds.txt.
public enum BoundsDiagnostics {
    public static func run(bundleID: String) {
        var out = ["program: \(bundleID)", "tilladelse: \(AXIsProcessTrusted())"]
        defer {
            let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/Baymow")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? out.joined(separator: "\n").write(to: dir.appendingPathComponent("ax-bounds.txt"), atomically: true, encoding: .utf8)
        }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            out.append("kører ikke"); return
        }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 2)
        var candidates: [(String, AXUIElement)] = []
        var focused: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
           let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() {
            candidates.append(("fokuseret element", focused as! AXUIElement))
        }
        var window: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &window) == .success,
           let window, CFGetTypeID(window) == AXUIElementGetTypeID() {
            for area in TextCaptureService.webAreas(in: window as! AXUIElement) { candidates.append(("webområde", area)) }
        }
        if candidates.isEmpty { out.append("intet fokuseret element eller webområde") }
        for (label, element) in candidates.prefix(3) {
            out.append("== \(label): rolle \(string(element, kAXRoleAttribute))")
            var names: CFArray?
            AXUIElementCopyParameterizedAttributeNames(element, &names)
            let parameterNames = (names as? [String]) ?? []
            out.append("  parametriserede: " + parameterNames.filter { $0.contains("Marker") || $0.contains("Bounds") || $0.contains("Index") || $0.contains("Range") }.sorted().joined(separator: ", "))
            // Almindelig vej: AXBoundsForRange for de første 5 tegn.
            var cf = CFRange(location: 0, length: 5)
            let rangeValue = AXValueCreate(.cfRange, &cf)!
            out.append("  AXBoundsForRange(0,5): " + rectDescription(parameterized(element, kAXBoundsForRangeParameterizedAttribute, rangeValue)))
            var selected: CFTypeRef?
            out.append("  AXSelectedTextRange: \(AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selected).rawValue)")
            // Webvejen: markører fra starten af elementet.
            var start: CFTypeRef?
            let startErr = AXUIElementCopyAttributeValue(element, "AXStartTextMarker" as CFString, &start)
            out.append("  AXStartTextMarker: \(startErr.rawValue)")
            if let start {
                let index = parameterized(element, "AXIndexForTextMarker", start)
                out.append("  AXIndexForTextMarker(start): \((index as? NSNumber)?.stringValue ?? "intet")")
                let five = parameterized(element, "AXTextMarkerForIndex", NSNumber(value: ((index as? NSNumber)?.intValue ?? 0) + 5))
                out.append("  AXTextMarkerForIndex(+5): \(five == nil ? "intet" : "ok")")
                var next: CFTypeRef? = start
                for _ in 0..<5 { next = next.flatMap { parameterized(element, "AXNextTextMarkerForTextMarker", $0) } }
                out.append("  AXNextTextMarkerForTextMarker ×5: \(next == nil ? "intet" : "ok")")
                for (name, end) in [("index", five), ("næste×5", next)] {
                    guard let end else { continue }
                    let range = parameterized(element, "AXTextMarkerRangeForUnorderedTextMarkers", [start, end] as CFArray)
                        ?? parameterized(element, "AXTextMarkerRangeForTextMarkers", [start, end] as CFArray)
                    out.append("  område (\(name)): \(range == nil ? "intet" : "ok")")
                    if let range {
                        out.append("  AXBoundsForTextMarkerRange (\(name)): " + rectDescription(parameterized(element, "AXBoundsForTextMarkerRange", range)))
                        let length = parameterized(element, "AXLengthForTextMarkerRange", range)
                        out.append("  AXLengthForTextMarkerRange (\(name)): \((length as? NSNumber)?.stringValue ?? "intet")")
                    }
                }
            }
            var markerRange: CFTypeRef?
            out.append("  AXSelectedTextMarkerRange: \(AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &markerRange).rawValue)")
        }
    }

    private static func parameterized(_ element: AXUIElement, _ attribute: String, _ parameter: CFTypeRef) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyParameterizedAttributeValue(element, attribute as CFString, parameter, &result) == .success ? result : nil
    }

    private static func rectDescription(_ value: CFTypeRef?) -> String {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return "intet" }
        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect) else { return "ikke et rektangel" }
        return String(format: "%.0f×%.0f ved (%.0f, %.0f)", rect.width, rect.height, rect.minX, rect.minY)
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return (value as? String) ?? "–"
    }
}

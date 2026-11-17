import AppKit
import ApplicationServices
import BaymowCore

/// Udviklerværktøj: beskriver, hvad et kørende program udstiller via Accessibility.
///
/// Rapporten indeholder kun roller, attributnavne, fejlkoder og tekstlængder – aldrig selve teksten.
/// Køres med `open -n Baymow.app --args --ax-diagnose <bundle-id>`, så macOS bruger appens egen
/// Tilgængelighed-tilladelse. Resultatet skrives til `~/Library/Logs/Baymow/ax-diagnose.txt`.
public enum AccessibilityDiagnostics {
    public static func run(bundleID: String) {
        var lines: [String] = ["bundle: \(bundleID)", "trusted: \(AXIsProcessTrusted())"]
        defer {
            let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/Baymow")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? lines.joined(separator: "\n").write(to: dir.appendingPathComponent("ax-diagnose.txt"), atomically: true, encoding: .utf8)
        }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            lines.append("programmet kører ikke")
            return
        }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 2.0)

        var ref: CFTypeRef?
        let focusErr = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &ref)
        lines.append("app.AXFocusedUIElement: err=\(focusErr.rawValue)")
        if focusErr == .success, let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() {
            var element: AXUIElement? = (ref as! AXUIElement)
            var depth = 0
            while let current = element, depth < 8 {
                lines.append("-- fokuseret element, niveau \(depth)")
                lines.append(contentsOf: describe(current))
                var parent: CFTypeRef?
                if AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parent) == .success,
                   let parent, CFGetTypeID(parent) == AXUIElementGetTypeID() {
                    element = (parent as! AXUIElement)
                } else {
                    element = nil
                }
                depth += 1
            }
        }

        let manualErr = AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        lines.append("sæt AXManualAccessibility: err=\(manualErr.rawValue)")
        // Forsøg: slår AXEnhancedUserInterface midlertidigt til og gendanner værdien bagefter.
        let tryEnhanced = CommandLine.arguments.contains("--try-enhanced")
        var before: CFTypeRef?
        AXUIElementCopyAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, &before)
        lines.append("AXEnhancedUserInterface før: \((before as? Bool).map(String.init) ?? "–")")
        if tryEnhanced {
            let err = AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            lines.append("sæt AXEnhancedUserInterface: err=\(err.rawValue)")
        }
        defer {
            if tryEnhanced, (before as? Bool) != true {
                AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
            }
        }
        Thread.sleep(forTimeInterval: 0.8)

        var windowRef: CFTypeRef?
        let windowErr = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef)
        lines.append("app.AXFocusedWindow: err=\(windowErr.rawValue)")
        if windowErr == .success, let windowRef, CFGetTypeID(windowRef) == AXUIElementGetTypeID() {
            let begin = Date()
            let areas = TextCaptureService.webAreas(in: windowRef as! AXUIElement)
            lines.append("søgning efter webområder: \(Int(Date().timeIntervalSince(begin) * 1000)) ms")
            lines.append("AXWebArea fundet i vinduet: \(areas.count)")
            for area in areas {
                lines.append("-- webområde")
                lines.append(contentsOf: describe(area))
            }
        }
    }

    private static func describe(_ element: AXUIElement) -> [String] {
        var out: [String] = []
        out.append("  rolle: \(string(element, kAXRoleAttribute)) / \(string(element, kAXSubroleAttribute))")

        var names: CFArray?
        AXUIElementCopyAttributeNames(element, &names)
        let attributes = (names as? [String]) ?? []
        out.append("  attributter med 'Select' eller 'Marker': \(attributes.filter { $0.contains("Select") || $0.contains("Marker") })")

        var value: CFTypeRef?
        let textErr = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value)
        out.append("  AXSelectedText: err=\(textErr.rawValue) længde=\((value as? String)?.count ?? -1)")

        var range: CFTypeRef?
        let rangeErr = AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &range)
        var markerLength = -1
        var stringErr: AXError = .failure
        if rangeErr == .success, let range {
            var string: CFTypeRef?
            stringErr = AXUIElementCopyParameterizedAttributeValue(element, "AXStringForTextMarkerRange" as CFString, range, &string)
            markerLength = (string as? String)?.count ?? -1
        }
        out.append("  AXSelectedTextMarkerRange: err=\(rangeErr.rawValue) → AXStringForTextMarkerRange: err=\(stringErr.rawValue) længde=\(markerLength)")
        return out
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return (value as? String) ?? "–"
    }
}

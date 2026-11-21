import Foundation
import ApplicationServices

/// Hvor den markerede tekst sidder i kildeprogrammet, så ord i den kan findes på skærmen (fremhævning direkte i
/// teksten, I1). Indeholder en reference til tekstfeltet og markeringens start – aldrig selve teksten. Slippes, når
/// oplæsningen lukkes.
public final class SelectionAnchor: @unchecked Sendable {
    enum Kind {
        /// Almindeligt tekstfelt: markeringen starter ved dette tegn (AXSelectedTextRange).
        case textRange(start: Int)
        /// Webindhold (WebKit): markeringen starter ved dette tegn (AXIndexForTextMarker).
        case webMarkers(start: Int)
    }

    let element: AXUIElement
    let kind: Kind
    /// Kildeprogrammet. Markeringen vises kun, når det er forrest.
    public let processIdentifier: pid_t

    init(element: AXUIElement, kind: Kind, processIdentifier: pid_t) {
        self.element = element
        self.kind = kind
        self.processIdentifier = processIdentifier
    }

    /// Skærmrektanglet for et stykke af den markerede tekst (UTF-16 i forhold til markeringens start), i Quartz-
    /// koordinater (øverste venstre hjørne af hovedskærmen er 0,0). `nil`, hvis programmet ikke oplyser det.
    /// Kalder programmet via Tilgængelighed og kan tage lidt tid – kald ikke på hovedtråden.
    public func screenRect(forSelectedRange range: NSRange) -> CGRect? {
        guard range.length > 0 else { return nil }
        let rect: CGRect?
        switch kind {
        case .textRange(let start):
            var cfRange = CFRange(location: start + range.location, length: range.length)
            guard let value = AXValueCreate(.cfRange, &cfRange) else { return nil }
            rect = Self.rect(from: parameterized(kAXBoundsForRangeParameterizedAttribute, value))
        case .webMarkers(let start):
            guard let first = parameterized("AXTextMarkerForIndex", NSNumber(value: start + range.location)),
                  let last = parameterized("AXTextMarkerForIndex", NSNumber(value: start + NSMaxRange(range))),
                  let markers = parameterized("AXTextMarkerRangeForUnorderedTextMarkers", [first, last] as CFArray) else {
                return nil
            }
            rect = Self.rect(from: parameterized("AXBoundsForTextMarkerRange", markers))
        }
        guard let rect, rect.width > 0, rect.height > 0 else { return nil }
        return rect
    }

    private func parameterized(_ attribute: String, _ parameter: CFTypeRef) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, attribute as CFString, parameter, &result) == .success else {
            return nil
        }
        return result
    }

    private static func rect(from value: CFTypeRef?) -> CGRect? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        return AXValueGetValue(value as! AXValue, .cgRect, &rect) ? rect : nil
    }

    /// Opretter et anker for en markering, der lige er hentet fra `element`, hvis programmet oplyser, hvor den starter.
    static func make(element: AXUIElement, method: DiagnosticsService.CaptureMethod, markerRange: CFTypeRef?,
                     processIdentifier: pid_t) -> SelectionAnchor? {
        switch method {
        case .accessibility:
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
                  let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
            var range = CFRange()
            guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
            return SelectionAnchor(element: element, kind: .textRange(start: range.location), processIdentifier: processIdentifier)
        case .webTextMarker:
            guard let markerRange else { return nil }
            var startMarker: CFTypeRef?
            var index: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(element, "AXStartTextMarkerForTextMarkerRange" as CFString,
                                                             markerRange, &startMarker) == .success, let startMarker,
                  AXUIElementCopyParameterizedAttributeValue(element, "AXIndexForTextMarker" as CFString,
                                                             startMarker, &index) == .success,
                  let start = (index as? NSNumber)?.intValue else { return nil }
            return SelectionAnchor(element: element, kind: .webMarkers(start: start), processIdentifier: processIdentifier)
        case .clipboard:
            return nil
        }
    }
}

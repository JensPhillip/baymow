import AppKit
import ApplicationServices
import Carbon.HIToolbox

public struct CapturedText: Sendable {
    public let text: String
    public let sourceBundleID: String?
    public let sourceAppName: String?
    public let method: DiagnosticsService.CaptureMethod
}

public struct CaptureFailure: Error, Sendable {
    public let notice: Notice
    public let sourceBundleID: String?
}

/// Henter den markerede tekst fra programmet, der er forrest.
///
/// Rækkefølge:
/// 1. Accessibility: `AXSelectedText` på det fokuserede element.
/// 2. Accessibility (WebKit): `AXSelectedTextMarkerRange` → `AXStringForTextMarkerRange`.
/// 3. Fallback: simuleret ⌘C, hvor udklipsholderens tidligere indhold gendannes bagefter.
///
/// Intet her er specifikt for bestemte hjemmesider eller programmer.
public final class TextCaptureService: Sendable {
    public init() {}

    public static var hasPermission: Bool { AXIsProcessTrusted() }

    /// Viser macOS' egen dialog, der sender brugeren til Tilgængelighed-indstillingerne.
    public static func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    public static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    public func capture() async -> Result<CapturedText, CaptureFailure> {
        let app = await MainActor.run { NSWorkspace.shared.frontmostApplication }
        let bundleID = app?.bundleIdentifier
        let appName = app?.localizedName

        guard Self.hasPermission else {
            return .failure(CaptureFailure(notice: .noPermission, sourceBundleID: bundleID))
        }
        guard let app else {
            return .failure(CaptureFailure(notice: .unsupported, sourceBundleID: nil))
        }

        // AX-kald er synkron IPC til et andet program, så de holdes væk fra hovedtråden.
        let pid = app.processIdentifier
        let ax = await Task.detached(priority: .userInitiated) { Self.readSelectionViaAccessibility(pid: pid) }.value
        if let text = ax.text {
            return .success(CapturedText(text: text, sourceBundleID: bundleID, sourceAppName: appName, method: ax.method))
        }

        if let text = await readSelectionViaClipboard() {
            return .success(CapturedText(text: text, sourceBundleID: bundleID, sourceAppName: appName, method: .clipboard))
        }

        // Kunne vi finde et fokuseret element, men ingen tekst, er der sandsynligvis intet markeret.
        // Kunne vi slet ikke tale med programmet, er det nok ikke understøttet.
        let notice: Notice = ax.foundFocusedElement ? .noSelection : .unsupported
        return .failure(CaptureFailure(notice: notice, sourceBundleID: bundleID))
    }

    // MARK: - Accessibility

    private struct AXResult {
        var text: String?
        var method: DiagnosticsService.CaptureMethod = .accessibility
        var foundFocusedElement = false
    }

    private static func readSelectionViaAccessibility(pid: pid_t) -> AXResult {
        var result = AXResult()
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 1.0)

        // Beder Chromium-/Electron-programmer om at bygge deres tilgængelighedstræ.
        // Ignoreres af programmer, der ikke kender attributten.
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        var focusedRef: CFTypeRef?
        var err = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        if err != .success {
            let system = AXUIElementCreateSystemWide()
            AXUIElementSetMessagingTimeout(system, 1.0)
            err = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        }
        if err == .success, let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() {
            result.foundFocusedElement = true
            if let hit = selection(in: focusedRef as! AXUIElement) {
                result.text = hit.text
                result.method = hit.method
                return result
            }
        }

        // Browsere melder ikke altid et fokuseret element, og et fokuseret underelement kender
        // ikke nødvendigvis markeringen. Sidens webområde gør: spørg det direkte.
        var windowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
           let windowRef, CFGetTypeID(windowRef) == AXUIElementGetTypeID() {
            for area in webAreas(in: windowRef as! AXUIElement) {
                result.foundFocusedElement = true
                if let hit = selection(in: area) {
                    result.text = hit.text
                    result.method = hit.method
                    return result
                }
            }
        }
        return result
    }

    private static func selection(in element: AXUIElement) -> (text: String, method: DiagnosticsService.CaptureMethod)? {
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success,
           let text = usable(value as? String) {
            return (text, .accessibility)
        }
        var markerRange: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &markerRange) == .success,
           let markerRange {
            var string: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, "AXStringForTextMarkerRange" as CFString, markerRange, &string) == .success,
               let text = usable(string as? String) {
                return (text, .webTextMarker)
            }
        }
        return nil
    }

    /// Finder webområder (AXWebArea) i et vindue med en bredde-først-søgning af begrænset størrelse.
    public static func webAreas(in window: AXUIElement, maxVisited: Int = 400) -> [AXUIElement] {
        var found: [AXUIElement] = []
        var queue: [AXUIElement] = [window]
        var visited = 0
        while !queue.isEmpty, visited < maxVisited {
            let element = queue.removeFirst()
            visited += 1
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
            if (role as? String) == "AXWebArea" {
                found.append(element)
                continue
            }
            var children: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
               let children = children as? [AXUIElement] {
                queue.append(contentsOf: children)
            }
        }
        return found
    }

    private static func usable(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    // MARK: - Udklipsholder-fallback

    /// Simulerer ⌘C, læser resultatet og gendanner derefter udklipsholderens tidligere indhold.
    private func readSelectionViaClipboard() async -> String? {
        let pasteboard = NSPasteboard.general
        let snapshot = Self.snapshot(of: pasteboard)
        let countBefore = pasteboard.changeCount

        // Genvejens egne ændringstaster (fx ⌃⌥) må ikke blande sig i ⌘C.
        await waitForModifierRelease()
        Self.postCopy()

        var copied: String?
        for _ in 0..<25 {
            try? await Task.sleep(nanoseconds: 20_000_000)
            if pasteboard.changeCount != countBefore {
                copied = Self.usable(pasteboard.string(forType: .string))
                break
            }
        }

        if pasteboard.changeCount != countBefore {
            Self.restore(snapshot, to: pasteboard)
        }
        return copied
    }

    private func waitForModifierRelease() async {
        let mask: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
        for _ in 0..<40 {
            if CGEventSource.flagsState(.combinedSessionState).intersection(mask).isEmpty { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private static func postCopy() {
        let source = CGEventSource(stateID: .privateState)
        let keyC = keyCodeForCopy()
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }

    /// Tasten, der giver "c" på det aktive tastaturlayout (fx Dvorak), så ⌘C rammer rigtigt.
    private static func keyCodeForCopy() -> CGKeyCode {
        let fallback: CGKeyCode = 8
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return fallback }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw -> CGKeyCode in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return fallback }
            for code in 0..<UInt16(128) {
                var deadKeys: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                                            OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
                if status == noErr, length == 1, chars[0] == UniChar(UInt8(ascii: "c")) { return code }
            }
            return fallback
        }
    }

    private static func snapshot(of pasteboard: NSPasteboard) -> [[(NSPasteboard.PasteboardType, Data)]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
    }

    private static func restore(_ snapshot: [[(NSPasteboard.PasteboardType, Data)]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let items = snapshot.map { entries -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entries { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }
}

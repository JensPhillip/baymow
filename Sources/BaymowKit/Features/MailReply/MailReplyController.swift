import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import SwiftUI
import BaymowCore

/// Mail-svarets indstillinger. Slået fra som standard; kræver "Bedre hjælp via internet" (siden Stavning).
@MainActor
final class MailReplySettings: ObservableObject {
    /// ⌃⌥M – "M" for mail.
    nonisolated static let standardShortcut = Shortcut(keyCode: UInt32(kVK_ANSI_M),
                                                       modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue, keyLabel: "M")
    static let standardTone = "Menneskelig og formel"

    private let defaults: UserDefaults
    @Published var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: "mailReplyEnabled") } }
    @Published var tone: String { didSet { defaults.set(tone, forKey: "mailReplyTone") } }
    /// Brugerens navn, så Baymow kan se, når den nyeste mail er brugerens egen (en opfølgning). Standard: Macens navn.
    @Published var yourName: String { didSet { defaults.set(yourName, forKey: "mailReplyName") } }
    /// Brugeren har en fast signatur i mailprogrammet: svaret får aldrig hilsen eller navn til sidst.
    @Published var hasStandardSignature: Bool { didSet { defaults.set(hasStandardSignature, forKey: "mailReplySignature") } }
    /// Firmaet, der skriver mail-svar – kan være et andet end stavehjælpens. Standard: ChatGPT.
    @Published var provider: CloudProvider { didSet { defaults.set(provider.rawValue, forKey: "mailReplyProvider") } }
    @Published var shortcut: Shortcut {
        didSet {
            defaults.set(Int(shortcut.keyCode), forKey: "mailShortcut.keyCode")
            defaults.set(Int(shortcut.modifiers), forKey: "mailShortcut.modifiers")
            defaults.set(shortcut.keyLabel, forKey: "mailShortcut.keyLabel")
        }
    }
    @Published var shortcutFailed = false

    /// Sparring om den åbne mail (AP-74). Slået fra som standard; egen genvej (⌃⌥K).
    nonisolated static let standardSparringShortcut = Shortcut(keyCode: UInt32(kVK_ANSI_K),
                                                               modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue, keyLabel: "K")
    @Published var sparringEnabled: Bool { didSet { defaults.set(sparringEnabled, forKey: "mailSparringEnabled") } }
    @Published var sparringShortcut: Shortcut {
        didSet {
            defaults.set(Int(sparringShortcut.keyCode), forKey: "sparringShortcut.keyCode")
            defaults.set(Int(sparringShortcut.modifiers), forKey: "sparringShortcut.modifiers")
            defaults.set(sparringShortcut.keyLabel, forKey: "sparringShortcut.keyLabel")
        }
    }
    @Published var sparringShortcutFailed = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: "mailReplyEnabled")
        tone = defaults.string(forKey: "mailReplyTone") ?? Self.standardTone
        yourName = defaults.string(forKey: "mailReplyName") ?? NSFullUserName()
        hasStandardSignature = defaults.object(forKey: "mailReplySignature") as? Bool ?? true
        provider = CloudProvider(rawValue: defaults.string(forKey: "mailReplyProvider") ?? "") ?? .openai
        sparringEnabled = defaults.bool(forKey: "mailSparringEnabled")
        if defaults.object(forKey: "sparringShortcut.keyCode") != nil, let label = defaults.string(forKey: "sparringShortcut.keyLabel") {
            sparringShortcut = Shortcut(keyCode: UInt32(defaults.integer(forKey: "sparringShortcut.keyCode")),
                                        modifiers: UInt(defaults.integer(forKey: "sparringShortcut.modifiers")), keyLabel: label)
        } else {
            sparringShortcut = Self.standardSparringShortcut
        }
        if defaults.object(forKey: "mailShortcut.keyCode") != nil, let label = defaults.string(forKey: "mailShortcut.keyLabel") {
            shortcut = Shortcut(keyCode: UInt32(defaults.integer(forKey: "mailShortcut.keyCode")),
                                modifiers: UInt(defaults.integer(forKey: "mailShortcut.modifiers")), keyLabel: label)
        } else {
            shortcut = Self.standardShortcut
        }
    }
}

/// Læser svarfeltet i mailprogrammet: hele feltet via tekstmarkører (rører hverken markering eller udklipsholder) og
/// stikordene med ⇧⌘↑ fra markøren, som så står markeret, klar til at blive erstattet af svaret.
///
/// Målt i Apple Mail 23. november 2026 (`--mail-probe`): hele feltet kan læses via tekstmarkører, og citat-overskriften
/// kan findes. Baymow kan ikke selv sætte markeringen præcist (signaturen standser den), derfor ⇧⌘↑.
@MainActor
enum MailReader {
    struct Captured {
        let whole: String
        let notes: String
        let bundleID: String?
    }

    enum Failure: Error, Equatable {
        /// Programmet udstiller ikke feltet (endnu ikke understøttet).
        case notSupported
        /// Markøren stod nede i tråden, så ⇧⌘↑ ville have taget for meget.
        case caretInThread
    }

    static func read() async -> Result<Captured, Failure> {
        guard let app = NSWorkspace.shared.frontmostApplication else { return .failure(.notSupported) }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 2.0)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXUIElementGetTypeID(),
              let whole = wholeText(of: ref as! AXUIElement) else { return .failure(.notSupported) }

        await waitForModifierRelease()
        let pasteboard = NSPasteboard.general
        let saved = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        let before = pasteboard.changeCount
        press(0x7E, [.maskCommand, .maskShift]) // ⇧⌘↑: markér fra markøren op til toppen
        try? await Task.sleep(nanoseconds: 150_000_000)
        press(SelectionReplacer.keyCode(for: "c"), [.maskCommand])
        for _ in 0..<12 where pasteboard.changeCount == before { try? await Task.sleep(nanoseconds: 50_000_000) }
        let notes = pasteboard.changeCount != before ? (pasteboard.string(forType: .string) ?? "") : ""
        if pasteboard.changeCount != before {
            pasteboard.clearContents()
            pasteboard.writeObjects(saved.map { entries -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in entries { item.setData(data, forType: type) }
                return item
            })
        }
        if MailThread.quoteStart(in: notes) != nil {
            press(0x7C, []) // → fjerner markeringen igen
            return .failure(.caretInThread)
        }
        return .success(Captured(whole: whole, notes: notes, bundleID: app.bundleIdentifier))
    }

    static func wholeText(of element: AXUIElement) -> String? {
        var start: CFTypeRef?, end: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXStartTextMarker" as CFString, &start) == .success,
              AXUIElementCopyAttributeValue(element, "AXEndTextMarker" as CFString, &end) == .success,
              let start, let end else { return nil }
        var range: CFTypeRef?
        AXUIElementCopyParameterizedAttributeValue(element, "AXTextMarkerRangeForUnorderedTextMarkers" as CFString,
                                                   [start, end] as CFArray, &range)
        guard let range else { return nil }
        var text: CFTypeRef?
        AXUIElementCopyParameterizedAttributeValue(element, "AXStringForTextMarkerRange" as CFString, range, &text)
        return text as? String
    }

    static func press(_ key: CGKeyCode, _ flags: CGEventFlags) {
        let source = CGEventSource(stateID: .privateState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }

    /// Genvejens ⌃⌥ må være sluppet, før Baymow trykker sine egne taster.
    private static func waitForModifierRelease() async {
        for _ in 0..<30 {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            if flags.intersection([.maskControl, .maskAlternate, .maskCommand, .maskShift]).isEmpty { return }
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
    }
}

/// Genvej → læs tråden og stikordene → ChatGPT/Claude skriver svaret → det sættes ind i stedet for stikordene.
@MainActor
final class MailReplyController {
    private let settings: MailReplySettings
    private let ai: AIServices
    private let speak: SpellingPanelModel.Speak
    private let stopSpeaking: () -> Void
    private let openSettings: () -> Void
    private var panel: NSPanel?
    private var model: MailReplyPanelModel?
    private var isWorking = false

    init(settings: MailReplySettings, ai: AIServices, speak: @escaping SpellingPanelModel.Speak,
         stopSpeaking: @escaping () -> Void, openSettings: @escaping () -> Void) {
        self.settings = settings
        self.ai = ai
        self.speak = speak
        self.stopSpeaking = stopSpeaking
        self.openSettings = openSettings
    }

    func run() {
        guard settings.isEnabled, !isWorking else { return }
        isWorking = true
        close()
        Task {
            defer { isWorking = false }
            let model = MailReplyPanelModel(speak: speak, stop: stopSpeaking)
            guard let cloud = ai.corrector(settings.provider, feature: .mail) else {
                model.state = .failed(.needsCloud)
                show(model)
                return
            }
            model.provider = cloud.provider
            let captured: MailReader.Captured
            switch await MailReader.read() {
            case .success(let result): captured = result
            case .failure(let failure):
                model.state = .failed(failure == .caretInThread ? .caretInThread : .notSupported)
                show(model)
                return
            }
            show(model)
            let parts = MailThread.split(whole: captured.whole, notes: captured.notes)
            let signature = parts.hasSignature || settings.hasStandardSignature
            let followUp = MailThread.latestIsFromUser(thread: parts.thread, name: settings.yourName)
            let reply: String
            do {
                let answer = try await cloud.send(
                    instructions: MailReplyPrompt.instructions(tone: settings.tone, hasSignature: signature,
                                                               name: settings.yourName, followUp: followUp),
                    prompt: MailReplyPrompt.prompt(notes: parts.notes, thread: parts.thread), maxTokens: 1200)
                let parsed = MailReplyPrompt.parse(answer)
                reply = MailReplyPrompt.clean(parsed.reply, hasSignature: signature, name: settings.yourName)
                model.assumptions = parsed.assumptions
                model.followUp = followUp
            } catch {
                MailReader.press(0x7C, []) // stikordene bliver stående; markeringen fjernes
                model.state = .failed(.cloud(error as? CloudSpellingError ?? .failed))
                resize()
                return
            }
            ai.usage.addCheck(cloud.provider, feature: .mail)
            guard self.model === model, !reply.isEmpty else { return }
            model.sourceBundleID = captured.bundleID
            // Direkte ind i mailen (brugerens valg), hvis mailprogrammet stadig er forrest; ellers kopieret.
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == captured.bundleID {
                await SelectionReplacer.replace(with: reply + (captured.notes.hasSuffix("\n") ? "\n" : ""))
                model.inserted = true
            } else {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(reply, forType: .string)
                model.inserted = false
            }
            model.state = .done(reply)
            resize()
        }
    }

    private func show(_ model: MailReplyPanelModel) {
        self.model = model
        let view = MailReplyPanelView(model: model, onUndo: { [weak self] in self?.undo() },
                                      onClose: { [weak self] in self?.close() },
                                      onSettings: { [weak self] in self?.close(); self?.openSettings() })
        let panel = FloatingPanel.make(content: view)
        self.panel = panel
        resize()
        panel.orderFrontRegardless()
    }

    private func resize() {
        guard let panel, let hosting = panel.contentView else { return }
        let size = hosting.fittingSize
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let top = panel.isVisible ? panel.frame.maxY : visible.maxY - 90
        let x = panel.isVisible ? panel.frame.minX : visible.maxX - size.width - 24
        panel.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
    }

    /// Fortryd: ⌘Z i mailprogrammet giver stikordene tilbage.
    private func undo() {
        guard let model, model.inserted,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == model.sourceBundleID else { return }
        MailReader.press(SelectionReplacer.keyCode(for: "z"), [.maskCommand])
        close()
    }

    func close() {
        stopSpeaking()
        panel?.orderOut(nil)
        panel = nil
        model = nil
    }
}

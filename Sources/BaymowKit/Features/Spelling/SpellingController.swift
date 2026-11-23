import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI
import BaymowCore

/// Stavehjælpens indstillinger. Slået fra som standard (planens afsnit 3).
@MainActor
final class SpellingSettings: ObservableObject {
    /// ⌃⌥R – "R" for "ret".
    nonisolated static let shortcut = Shortcut(keyCode: UInt32(kVK_ANSI_R),
                                   modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue, keyLabel: "R")

    private let defaults: UserDefaults
    @Published var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: "spellingHelpEnabled") } }
    /// Sat, hvis genvejen ikke kunne registreres (fx optaget af et andet program).
    @Published var shortcutFailed = false
    @Published var modelStatus: SpellingModelStatus = AppleSpellingModel.status()

    /// Bedre hjælp via internet (AP-64). Slået fra som standard; kræver brugerens egen nøgle.
    @Published var cloudEnabled: Bool { didSet { defaults.set(cloudEnabled, forKey: "spellingCloudEnabled") } }
    @Published var cloudProvider: CloudProvider {
        didSet { defaults.set(cloudProvider.rawValue, forKey: "spellingCloudProvider"); testResult = nil }
    }
    /// Hvilke firmaer der er gemt en nøgle til. Selve nøglen ligger kun i nøgleringen.
    @Published private(set) var savedKeys: Set<CloudProvider> = []
    @Published var testResult: CloudTestResult?

    enum CloudTestResult: Equatable { case testing, ok, failed(CloudSpellingError) }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        usage = CloudUsageLog(defaults: defaults)
        isEnabled = defaults.bool(forKey: "spellingHelpEnabled")
        cloudEnabled = defaults.bool(forKey: "spellingCloudEnabled")
        cloudProvider = CloudProvider(rawValue: defaults.string(forKey: "spellingCloudProvider") ?? "") ?? .openai
        refreshKeys()
    }

    func refreshKeys() {
        savedKeys = Set(CloudProvider.allCases.filter { CloudKeyStore.hasKey(for: $0) })
    }

    func saveKey(_ key: String) {
        CloudKeyStore.save(key, for: cloudProvider)
        refreshKeys()
        testResult = nil
    }

    func deleteKey() {
        CloudKeyStore.delete(cloudProvider)
        refreshKeys()
        testResult = nil
    }

    /// Internet-retteren, hvis den er slået til, og der er en nøgle. Ellers `nil`: så bruges Macens egen hjælp.
    func cloudCorrector() -> CloudSpellingCorrector? {
        guard cloudEnabled, let key = CloudKeyStore.key(for: cloudProvider) else { return nil }
        return corrector(key: key)
    }

    /// Forbruget af internet-hjælpen (kun tal).
    let usage: CloudUsageLog

    private func corrector(key: String) -> CloudSpellingCorrector {
        let provider = cloudProvider
        let usage = usage
        return CloudSpellingCorrector(provider: provider, key: key, onUsage: { input, output in
            Task { @MainActor in usage.addTokens(provider, input: input, output: output) }
        })
    }

    /// Brugeren trykker "Prøv": sender en fast testsætning (aldrig brugerens tekst) og viser, om nøglen virker.
    func testConnection() {
        guard let key = CloudKeyStore.key(for: cloudProvider) else { testResult = .failed(.noKey); return }
        let corrector = corrector(key: key)
        usage.addCheck(cloudProvider)
        testResult = .testing
        Task {
            do {
                try await corrector.test()
                testResult = .ok
            } catch {
                testResult = .failed(error as? CloudSpellingError ?? .failed)
            }
        }
    }

    func refreshModelStatus() {
        let status = AppleSpellingModel.status()
        if status != modelStatus { modelStatus = status }
    }
}

/// Genvej → markeret egen tekst → lille vindue med rettelser → "Brug rettelsen" erstatter markeringen.
@MainActor
final class SpellingController {
    private let capture: TextCaptureService
    private let settings: SpellingSettings
    private let speak: (String, Language) -> Void
    private let stopSpeaking: () -> Void
    private let onFailure: (Notice) -> Void
    private var panel: NSPanel?
    private var model: SpellingPanelModel?
    private var isWorking = false

    init(capture: TextCaptureService, settings: SpellingSettings, speak: @escaping (String, Language) -> Void,
         stopSpeaking: @escaping () -> Void, onFailure: @escaping (Notice) -> Void) {
        self.capture = capture
        self.settings = settings
        self.speak = speak
        self.stopSpeaking = stopSpeaking
        self.onFailure = onFailure
    }

    func run() {
        guard settings.isEnabled, !isWorking else { return }
        isWorking = true
        close()
        Task {
            defer { isWorking = false }
            let captured: (text: String, bundleID: String?)
            if let own = OwnWindowSelection.text() {
                captured = (own, Bundle.main.bundleIdentifier)
            } else {
                switch await capture.capture() {
                case .success(let result): captured = (result.text, result.sourceBundleID)
                case .failure(let failure): onFailure(failure.notice); return
                }
            }
            settings.refreshModelStatus()
            let model = SpellingPanelModel(sourceBundleID: captured.bundleID, speak: speak)
            model.chosenProvider = settings.cloudProvider
            show(model)
            guard captured.text.count <= SpellingAssistant.maximumLength else {
                model.state = .tooLong
                resize()
                return
            }
            let local = AppleSpellingModel.makeCorrector()
            let cloud = settings.cloudCorrector()
            let assistant = SpellingAssistant(corrector: cloud ?? local, fallback: cloud == nil ? nil : local,
                                              checker: SystemWordChecker())
            var result = await assistant.check(captured.text)
            if settings.cloudEnabled, cloud == nil, result.cloudProblem == nil { result.cloudProblem = .noKey }
            if let cloud, result.cloudProblem == nil { settings.usage.addCheck(cloud.provider) }
            guard self.model === model else { return } // lukket undervejs
            model.load(result)
            resize()
        }
    }

    private func show(_ model: SpellingPanelModel) {
        self.model = model
        let view = SpellingPanelView(model: model, onApply: { [weak self] in self?.apply() },
                                     onCopy: { [weak self] in self?.copy() }, onClose: { [weak self] in self?.close() })
        let panel = FloatingPanel.make(content: view)
        self.panel = panel
        resize()
        panel.orderFrontRegardless()
    }

    /// Vinduet følger indholdet; øverste kant står fast, så det ikke hopper.
    private func resize() {
        guard let panel, let hosting = panel.contentView else { return }
        let size = hosting.fittingSize
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let top = panel.isVisible ? panel.frame.maxY : visible.maxY - 90
        let x = panel.isVisible ? panel.frame.minX : visible.midX - size.width / 2
        panel.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
    }

    func close() {
        stopSpeaking()
        panel?.orderOut(nil)
        panel = nil
        model = nil
    }

    private func copy() {
        guard let model else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(model.text, forType: .string)
        model.copied = true
    }

    /// Erstatter markeringen i programmet, teksten kom fra. Er brugeren skiftet til et andet program, kopieres teksten
    /// i stedet, så den ikke havner det forkerte sted.
    private func apply() {
        guard let model else { return }
        let text = model.text
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard front == model.sourceBundleID, front != Bundle.main.bundleIdentifier else {
            copy()
            model.pasteHint = true
            return
        }
        close()
        Task { await SelectionReplacer.replace(with: text) }
    }
}

/// Sætter tekst ind i stedet for markeringen med et simuleret ⌘V. Udklipsholderens indhold gendannes bagefter.
@MainActor
enum SelectionReplacer {
    static func replace(with text: String) async {
        let pasteboard = NSPasteboard.general
        let saved = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        // Udklipsholder-programmer bedes om ikke at gemme teksten (nspasteboard.org).
        item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        pasteboard.writeObjects([item])
        let changeAfterWrite = pasteboard.changeCount

        let source = CGEventSource(stateID: .privateState)
        let key = keyCode(for: "v")
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)

        // Programmet skal nå at læse udklipsholderen, før den gendannes.
        try? await Task.sleep(nanoseconds: 700_000_000)
        guard pasteboard.changeCount == changeAfterWrite else { return } // brugeren har selv kopieret noget imens
        pasteboard.clearContents()
        let items = saved.map { entries -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entries { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }

    /// Tasten, der giver bogstavet på det aktive tastaturlayout (fx Dvorak). Kun på hovedtråden (TIS).
    static func keyCode(for letter: Character) -> CGKeyCode {
        let fallback = CGKeyCode(kVK_ANSI_V)
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData),
              let ascii = letter.asciiValue else { return fallback }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw -> CGKeyCode in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return fallback }
            for code in 0..<UInt16(128) {
                var deadKeys: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                                            OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
                if status == noErr, length == 1, chars[0] == UniChar(ascii) { return code }
            }
            return fallback
        }
    }
}

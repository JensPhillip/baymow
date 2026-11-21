import AppKit
import AVFoundation
import SwiftUI
import Combine
import BaymowCore

/// Applikationens livscyklus: hovedvindue, menulinje og sammenkobling af tjenesterne.
@MainActor
public final class AppShell: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let settings = SettingsStore()
    private let diagnostics = DiagnosticsService()
    private let capture = TextCaptureService()
    private let shortcuts = GlobalShortcutManager()
    private let voiceStore = VoiceStore()
    private lazy var piperBackend = PiperBackend(store: voiceStore)
    private lazy var piper = BackendSpeechEngine(backend: piperBackend)
    private lazy var downloader = ModelDownloader(store: voiceStore)
    private lazy var catalog = VoiceCatalog(engines: [piper, AppleSpeechEngine()], settings: settings)
    private lazy var sessions = ReadingSessionManager(catalog: catalog, settings: settings, diagnostics: diagnostics)
    private lazy var player = FloatingPlayer(sessions: sessions, settings: settings)
    private lazy var notices = NoticePresenter(settings: settings)
    /// Ordfremhævning (I1). Gør intet, før brugeren slår den til.
    private lazy var readingWindow = ReadingWindowController(sessions: sessions, settings: settings)
    private lazy var windowModel = MainWindowModel(settings: settings, catalog: catalog, downloader: downloader,
                                                       sampleEngines: [AppleSpeechEngine(), BackendSpeechEngine(backend: piperBackend)])

    private lazy var onboarding = OnboardingWindowController(
        model: OnboardingModel(settings: settings, catalog: catalog, sampleEngine: AppleSpeechEngine()))

    private var statusItem: NSStatusItem?
    private var readMenuItem: NSMenuItem?
    private var mainWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []
    private var isCapturing = false
    private var shortcutRegistrationFailed = false

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        diagnostics.record(.appLaunched)
        buildMainMenu()
        buildStatusItem()

        downloader.onChange = { [weak self] in
            guard let self else { return }
            for voice in DownloadableVoice.catalog where !self.downloader.isInstalled(voice) {
                self.piperBackend.unload(voiceID: voice.id)
            }
            self.catalog.refresh()
            self.prepareNeuralVoices()
        }
        prepareNeuralVoices()

        // Henter brugeren en systemstemme (fx Sara (forbedret)), skal den kunne bruges uden genstart.
        NotificationCenter.default.addObserver(forName: AVSpeechSynthesizer.availableVoicesDidChangeNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.catalog.refresh() }
        }

        _ = readingWindow

        shortcuts.onTrigger = { [weak self] in self?.readSelection() }
        settings.$shortcut.removeDuplicates().sink { [weak self] shortcut in
            self?.registerShortcut(shortcut)
        }.store(in: &cancellables)

        // Første opstart: velkomstvinduet. Senere, hvis adgangen mangler: hovedvinduet, der forklarer det.
        if !settings.hasCompletedOnboarding {
            showOnboarding()
        } else if !TextCaptureService.hasPermission {
            showMainWindow()
        }
    }

    /// Appen fortsætter i menulinjen og lytter efter genvejen, når hovedvinduet lukkes.
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    /// Indlæser de valgte neurale stemmer på forhånd, så første oplæsning starter uden ventetid.
    private func prepareNeuralVoices() {
        for language in Language.allCases {
            if let voice = catalog.voice(for: language), voice.engineID == piper.engineID { piper.prepare(voice) }
        }
    }

    // MARK: - Oplæsning

    private func readSelection() {
        guard !isCapturing else { return }
        isCapturing = true
        let triggeredAt = Date()
        notices.dismiss()

        // Markeret tekst i Baymows eget vindue (eksempelteksten i "Kom i gang").
        if let own = OwnWindowSelection.text() {
            isCapturing = false
            if let notice = sessions.start(text: own, sourceAppName: "Baymow", sourceBundleID: Bundle.main.bundleIdentifier,
                                           triggeredAt: triggeredAt) {
                present(notice)
            } else {
                player.show()
                onboarding.model.readingStarted()
            }
            return
        }

        Task {
            let result = await capture.capture()
            isCapturing = false
            switch result {
            case .success(let captured):
                diagnostics.record(.captureSucceeded, sourceBundleID: captured.sourceBundleID, method: captured.method,
                                   milliseconds: Int(Date().timeIntervalSince(triggeredAt) * 1000))
                if let notice = sessions.start(text: captured.text, sourceAppName: captured.sourceAppName,
                                               sourceBundleID: captured.sourceBundleID, triggeredAt: triggeredAt) {
                    present(notice)
                } else {
                    player.show()
                    onboarding.model.readingStarted()
                }
            case .failure(let failure):
                switch failure.notice {
                case .noSelection: diagnostics.record(.captureNoSelection, sourceBundleID: failure.sourceBundleID)
                case .noPermission: diagnostics.record(.captureNoPermission, sourceBundleID: failure.sourceBundleID)
                case .unsupported, .noVoice, .tooLong: diagnostics.record(.captureUnsupported, sourceBundleID: failure.sourceBundleID)
                }
                present(failure.notice)
            }
        }
    }

    private func present(_ notice: Notice) {
        notices.show(notice, below: player.frame) { [weak self] in self?.showMainWindow() }
    }

    private func registerShortcut(_ shortcut: Shortcut) {
        let ok = shortcuts.register(shortcut)
        if !ok { diagnostics.record(.hotkeyRegistrationFailed) }
        if shortcutRegistrationFailed != !ok {
            shortcutRegistrationFailed = !ok
            refreshMainWindowContent()
        }
        readMenuItem?.title = "Læs markeret tekst (\(shortcut.displayString))"
    }

    // MARK: - Vinduer og menuer

    @objc public func showMainWindow() {
        if mainWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false
            )
            window.title = "Baymow"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            window.setFrameAutosaveName("BaymowMainWindow")
            mainWindow = window
            refreshMainWindowContent()
        }
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    private func refreshMainWindowContent() {
        mainWindow?.contentView = NSHostingView(rootView: MainView(
            model: windowModel, settings: settings, catalog: catalog, downloader: downloader,
            shortcutRegistrationFailed: shortcutRegistrationFailed
        ))
    }

    @objc private func readSelectionFromMenu() { readSelection() }

    @objc public func showOnboarding() { onboarding.show() }

    @objc public func showAbout() { AboutBaymow.show() }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "Baymow")

        let menu = NSMenu()
        let read = NSMenuItem(title: "Læs markeret tekst", action: #selector(readSelectionFromMenu), keyEquivalent: "")
        read.target = self
        menu.addItem(read)
        readMenuItem = read
        menu.addItem(.separator())
        let open = NSMenuItem(title: "Åbn Baymow", action: #selector(showMainWindow), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let welcome = NSMenuItem(title: "Kom i gang…", action: #selector(showOnboarding), keyEquivalent: "")
        welcome.target = self
        menu.addItem(welcome)
        let prefs = NSMenuItem(title: "Indstillinger…", action: #selector(showMainWindow), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        menu.addItem(.separator())
        let aboutItem = NSMenuItem(title: "Om Baymow", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        menu.addItem(NSMenuItem(title: "Afslut Baymow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    /// Minimal hovedmenu, så ⌘Q, ⌘W og ⌘, virker, når hovedvinduet er forrest.
    private func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let about = NSMenuItem(title: "Om Baymow", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        appMenu.addItem(about)
        appMenu.addItem(.separator())
        let prefs = NSMenuItem(title: "Indstillinger…", action: #selector(showMainWindow), keyEquivalent: ",")
        prefs.target = self
        appMenu.addItem(prefs)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Skjul Baymow", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: "Afslut Baymow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)

        // Rediger-menuen giver de almindelige genveje (⌘C, ⌘A …) i Baymows egne vinduer.
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Rediger")
        editMenu.addItem(NSMenuItem(title: "Fortryd", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Annuller fortryd", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Klip", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Kopiér", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Sæt ind", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Markér alt", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Vindue")
        windowMenu.addItem(NSMenuItem(title: "Luk vindue", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowMenu.addItem(NSMenuItem(title: "Minimer", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.mainMenu = main
    }
}

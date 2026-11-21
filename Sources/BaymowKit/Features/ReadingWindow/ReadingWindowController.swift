import AppKit
import Combine
import BaymowCore

/// Ordfremhævning (I1): et vindue, der viser teksten under oplæsningen og fremhæver ordet – eller sætningen –
/// der læses. Slås til og fra med `SettingsStore.showReadingWindow` (slået fra som standard).
///
/// Teksten hentes kun fra `ReadingSessionManager.textForDisplay()` og vises kun, mens sessionen lever. Den gemmes
/// ingen steder og fjernes fra vinduet, når det lukkes.
@MainActor
final class ReadingWindowController: NSObject, NSWindowDelegate {
    private let sessions: ReadingSessionManager
    private let settings: SettingsStore
    private var panel: NSPanel?
    private var textView: NSTextView?
    private var shownText: String?
    private var highlighted: NSRange?
    /// Brugeren har lukket vinduet under denne oplæsning; det kommer igen ved næste.
    private var closedForThisText = false
    private var cancellables: Set<AnyCancellable> = []

    static let fontSize: CGFloat = 20
    static let highlightColor = NSColor.systemYellow.withAlphaComponent(0.6)

    init(sessions: ReadingSessionManager, settings: SettingsStore) {
        self.sessions = sessions
        self.settings = settings
        super.init()
        // @Published melder før værdien er sat; vent til næste tur i løkken, så tilstanden er opdateret.
        Publishers.Merge(sessions.$state.map { _ in () }, settings.$showReadingWindow.map { _ in () })
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.update() }
            .store(in: &cancellables)
        sessions.$highlightRange
            .receive(on: RunLoop.main)
            .sink { [weak self] range in self?.highlight(range) }
            .store(in: &cancellables)
    }

    private func update() {
        guard settings.showReadingWindow, sessions.state != .idle, let text = sessions.textForDisplay() else {
            hide()
            return
        }
        if text != shownText {
            shownText = text
            closedForThisText = false
            show(text)
        } else if panel?.isVisible != true, !closedForThisText {
            panel?.orderFrontRegardless()
        }
    }

    private func show(_ text: String) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        guard let textView else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 7
        textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: Self.fontSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]))
        highlighted = nil
        textView.scrollToBeginningOfDocument(nil)
        panel.orderFrontRegardless()
        highlight(sessions.highlightRange)
    }

    private func hide() {
        panel?.orderOut(nil)
        // Teksten fjernes fra vinduet, så den ikke ligger i hukommelsen længere end sessionen.
        textView?.string = ""
        shownText = nil
        highlighted = nil
    }

    private func highlight(_ range: NSRange?) {
        guard let storage = textView?.textStorage, panel?.isVisible == true else { return }
        let length = storage.length
        if let old = highlighted, NSMaxRange(old) <= length {
            storage.removeAttribute(.backgroundColor, range: old)
            storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: old)
        }
        highlighted = nil
        guard let range, range.length > 0, NSMaxRange(range) <= length else { return }
        storage.addAttribute(.backgroundColor, value: Self.highlightColor, range: range)
        // Mørk tekst på gul baggrund er læselig i både lys og mørk tilstand.
        storage.addAttribute(.foregroundColor, value: NSColor.black, range: range)
        highlighted = range
        textView?.scrollRangeToVisible(range)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 320),
                            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.title = "Baymow – tekst"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 320, height: 160)
        panel.delegate = self

        let scroll = NSTextView.scrollableTextView()
        let view = scroll.documentView as! NSTextView
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = false
        view.textContainerInset = NSSize(width: 16, height: 14)
        view.setAccessibilityLabel("Teksten, der læses op")
        panel.contentView = scroll
        textView = view

        panel.center()
        panel.setFrameAutosaveName("BaymowReadingWindow")
        return panel
    }

    func windowWillClose(_ notification: Notification) {
        closedForThisText = true
        textView?.string = ""
        highlighted = nil
    }
}

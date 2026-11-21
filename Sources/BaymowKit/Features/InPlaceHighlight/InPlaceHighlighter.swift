import AppKit
import Combine
import BaymowCore

/// Fremhævning direkte i teksten (I1): et gennemsigtigt gult felt oven på ordet, der læses, der hvor teksten blev
/// markeret. Slås til og fra med `SettingsStore.highlightInPlace` (slået fra som standard).
///
/// Virker kun i programmer, der via Tilgængelighed oplyser, hvor teksten står (fx TextEdit, Noter, Safari, Mail). Hvor
/// teksten hentes med kopiering (fx Chrome og Word), er det ikke muligt – dér kan tekstvinduet bruges.
@MainActor
final class InPlaceHighlighter {
    private let sessions: ReadingSessionManager
    private let settings: SettingsStore
    private let overlay = HighlightOverlay()
    /// Tilgængelighedskald til andre programmer kan tage tid; de køres i rækkefølge uden for hovedtråden.
    private let queue = DispatchQueue(label: "baymow.inplace-highlight", qos: .userInteractive)

    private var anchor: SelectionAnchor?
    /// Kobler den viste tekst (sessionens) til den markerede tekst i programmet.
    private var alignment: WordAlignment?
    /// Tæller op ved hver ny position, så svar på gamle forespørgsler ignoreres.
    private var generation = 0
    private var cancellables: Set<AnyCancellable> = []

    init(sessions: ReadingSessionManager, settings: SettingsStore) {
        self.sessions = sessions
        self.settings = settings
        sessions.$highlightRange
            .receive(on: RunLoop.main)
            .sink { [weak self] range in self?.show(range) }
            .store(in: &cancellables)
        // @Published melder før værdien er sat, og her leveres meldingen først på næste tur i løkken. En ny oplæsning
        // lukker den gamle (tilstand "idle") og starter straks den nye – så når "idle" når frem, kører den nye måske
        // allerede. Kig derfor på den aktuelle tilstand, ikke den meldte (fejl fundet af brugeren 2026-11-21).
        sessions.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.sessions.state == .idle else { return }
                self.end()
            }
            .store(in: &cancellables)
        settings.$highlightInPlace
            .receive(on: RunLoop.main)
            .sink { [weak self] on in if !on { self?.overlay.hide() } }
            .store(in: &cancellables)
    }

    /// Kaldes, når en ny oplæsning er startet. `captured` er teksten, som den blev markeret i programmet.
    func begin(captured: String, anchor: SelectionAnchor?) {
        end()
        guard let anchor, let display = sessions.textForDisplay() else { return }
        self.anchor = anchor
        // Den viste tekst er renset for linjeskift o.l.; koblingen finder de samme ord i den markerede tekst.
        alignment = WordAlignment(original: captured, spoken: display)
    }

    /// Det gule felts placering lige nu, eller nil (bruges af selvtesten).
    var overlayFrame: CGRect? { overlay.visibleFrame }

    func end() {
        generation += 1
        anchor = nil
        alignment = nil
        overlay.hide()
    }

    private func show(_ displayRange: NSRange?) {
        generation += 1
        guard settings.highlightInPlace, let displayRange, let anchor, let alignment,
              let selectedRange = alignment.originalRange(forSpokenRange: displayRange) else {
            overlay.hide()
            return
        }
        let current = generation
        queue.async { [weak self] in
            let rect = anchor.screenRect(forSelectedRange: selectedRange)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.generation == current else { return }
                    // Kun når programmet med teksten er forrest – ellers ville feltet svæve over andre programmer.
                    guard let rect, NSWorkspace.shared.frontmostApplication?.processIdentifier == anchor.processIdentifier else {
                        self.overlay.hide()
                        return
                    }
                    self.overlay.show(at: Self.appKitRect(fromQuartz: rect))
                }
            }
        }
    }

    /// Tilgængelighed bruger Quartz-koordinater (0,0 øverst til venstre på hovedskærmen); vinduer bruger AppKit-
    /// koordinater (0,0 nederst til venstre).
    static func appKitRect(fromQuartz rect: CGRect, primaryScreenHeight: CGFloat? = nil) -> CGRect {
        let height = primaryScreenHeight ?? NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }
}

/// Det gule felt: et gennemsigtigt vindue uden ramme, som man kan klikke igennem.
@MainActor
final class HighlightOverlay {
    private var panel: NSPanel?
    static let padding: CGFloat = 2

    func show(at rect: CGRect) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setFrame(rect.insetBy(dx: -Self.padding, dy: -Self.padding), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// Feltets placering, når det vises (bruges af selvtesten).
    var visibleFrame: CGRect? { panel?.isVisible == true ? panel?.frame : nil }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.35).cgColor
        view.layer?.borderColor = NSColor.systemYellow.withAlphaComponent(0.95).cgColor
        view.layer?.borderWidth = 1.5
        view.layer?.cornerRadius = 3
        panel.contentView = view
        panel.setAccessibilityElement(false)
        return panel
    }
}

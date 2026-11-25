import AppKit
import Combine
import SwiftUI
import BaymowCore

/// Det, knapbjælkens vindue viser lige nu.
@MainActor
final class ActionBarModel: ObservableObject {
    @Published var style: ActionBarStyle = .hover
    @Published var buttons: [ActionBarButton] = []
    /// Knapperne er foldet ud.
    @Published var expanded = false
    /// Forklaringen, der vises ved musen.
    @Published var tip: ActionBarButton?
    /// Knapperne folder sig ud mod venstre (logoet står i højre side af skærmen).
    @Published var opensLeft = true
    /// Ligger bjælken i venstre kant (kun "Fast i skærmens kant").
    @Published var edgeOnLeft = false
    @Published var isListening = false

    /// Står knapperne fremme? "Altid synlig" er altid åben.
    var showsButtons: Bool { style == .floating || expanded }
}

/// Knapbjælken (AP-77): et lille vindue, der aldrig tager fokus fra det program, brugeren arbejder i. Derfor virker
/// "Læs op" på den tekst, brugeren har markeret – præcis som genvejen.
@MainActor
final class ActionBarController {
    private let settings: ActionBarSettings
    private let available: () -> Set<ActionBarButton>
    private let perform: (ActionBarButton) -> Void
    private let speak: SpellingPanelModel.Speak
    private let stopSpeaking: () -> Void
    private let model = ActionBarModel()
    static let sizingOptions: NSHostingSizingOptions = [.intrinsicContentSize]
    private var panel: NSPanel?
    private var cancellables: Set<AnyCancellable> = []
    private var hoverTask: Task<Void, Never>?
    private var tipTask: Task<Void, Never>?
    private var dragStart: (mouse: CGPoint, origin: CGPoint)?

    init(settings: ActionBarSettings, available: @escaping () -> Set<ActionBarButton>,
         perform: @escaping (ActionBarButton) -> Void, speak: @escaping SpellingPanelModel.Speak,
         stopSpeaking: @escaping () -> Void) {
        self.settings = settings
        self.available = available
        self.perform = perform
        self.speak = speak
        self.stopSpeaking = stopSpeaking
        settings.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.refresh() }
        }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.place(resetting: false) }.store(in: &cancellables)
    }

    /// Viser, skjuler eller opdaterer bjælken ud fra indstillingerne. Kaldes også, når en funktion slås til eller fra.
    func refresh() {
        let buttons = settings.visibleButtons(available: available())
        guard settings.isEnabled, !buttons.isEmpty else {
            panel?.orderOut(nil)
            panel = nil
            model.expanded = false
            return
        }
        let styleChanged = model.style != settings.style
        model.style = settings.style
        model.buttons = buttons
        model.edgeOnLeft = !settings.edgeOnRight
        if panel == nil { panel = makePanel() }
        if styleChanged { model.expanded = false; model.tip = nil }
        place(resetting: styleChanged || panel?.isVisible == false)
        panel?.orderFrontRegardless()
        DispatchQueue.main.async { [weak self] in self?.place(resetting: false) }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 60, height: 60),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let view = ActionBarHost(
            model: model,
            onHover: { [weak self] inside in self?.hover(inside) },
            onLogoTap: { [weak self] in self?.logoTapped() },
            onDrag: { [weak self] ended in self?.drag(ended: ended) },
            onButton: { [weak self] button in self?.pressed(button) },
            onButtonHover: { [weak self] button in self?.hoverButton(button) },
            onListen: { [weak self] in self?.listenToTip() })
        let hosting = NSHostingView(rootView: view)
        // Kun den naturlige størrelse (ikke vinduets min/max): Baymow sætter selv rammen, så logoet bliver stående.
        hosting.sizingOptions = Self.sizingOptions
        panel.contentView = hosting
        return panel
    }

    // MARK: Mus og klik

    private func hover(_ inside: Bool) {
        hoverTask?.cancel()
        guard model.style == .hover || model.style == .edge else { return }
        let target = inside
        // Et øjeblik før den folder sig ud (så den ikke springer op, når musen bare kommer forbi) og lidt længere,
        // før den folder sig sammen (så man kan nå at flytte musen hen til knappen).
        let delay: UInt64 = inside ? 350_000_000 : 700_000_000
        hoverTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard let self, !Task.isCancelled, self.model.expanded != target, self.dragStart == nil else { return }
            self.setExpanded(target)
        }
    }

    private func logoTapped() {
        switch model.style {
        case .dot, .hover, .edge: setExpanded(!model.expanded)
        case .floating: break
        }
    }

    private func pressed(_ button: ActionBarButton) {
        stopTip()
        if model.style != .floating { setExpanded(false) }
        perform(button)
    }

    private func setExpanded(_ expanded: Bool) {
        if !expanded { stopTip() }
        model.expanded = expanded
        placeSoon()
    }

    /// SwiftUI tegner om lidt efter en ændring; størrelsen måles bagefter.
    private func placeSoon() {
        place(resetting: false)
        DispatchQueue.main.async { [weak self] in self?.place(resetting: false) }
    }

    private func hoverButton(_ button: ActionBarButton?) {
        tipTask?.cancel()
        guard let button else {
            tipTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard let self, !Task.isCancelled, !self.model.isListening else { return }
                self.model.tip = nil
                self.placeSoon()
            }
            return
        }
        guard model.tip != button else { return }
        tipTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard let self, !Task.isCancelled else { return }
            if self.model.isListening { self.stopTip() }
            self.model.tip = button
            self.placeSoon()
        }
    }

    private func listenToTip() {
        guard let tip = model.tip else { return }
        if model.isListening { stopTip(keepTip: true); return }
        model.isListening = true
        speak(tip.help, .danish) { [weak self] in self?.model.isListening = false }
    }

    private func stopTip(keepTip: Bool = false) {
        if model.isListening { stopSpeaking() }
        model.isListening = false
        if !keepTip { model.tip = nil }
    }

    /// Logoet kan trækkes hen, hvor brugeren vil have det. I kanten kan det kun flyttes op og ned (og til den anden side).
    private func drag(ended: Bool) {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        if dragStart == nil { dragStart = (mouse, panel.frame.origin); hoverTask?.cancel() }
        guard let start = dragStart else { return }
        var origin = CGPoint(x: start.origin.x + mouse.x - start.mouse.x, y: start.origin.y + mouse.y - start.mouse.y)
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if model.style == .edge, let visible = screen?.visibleFrame {
            settings.edgeOnRight = mouse.x > visible.midX
            model.edgeOnLeft = !settings.edgeOnRight
            origin.x = settings.edgeOnRight ? visible.maxX - panel.frame.width : visible.minX
        }
        panel.setFrameOrigin(origin)
        guard ended else { return }
        dragStart = nil
        if model.style == .edge, let visible = screen?.visibleFrame {
            settings.edgeHeight = min(1, max(0, (panel.frame.midY - visible.minY) / max(visible.height, 1)))
        } else {
            settings.savedOrigin = logoCorner(of: panel.frame)
        }
        place(resetting: false)
    }

    // MARK: Placering

    /// Det hjørne, logoet sidder i: det står stille, mens knapperne folder sig ud og ind.
    private func logoCorner(of frame: CGRect) -> CGPoint {
        CGPoint(x: model.opensLeft ? frame.maxX : frame.minX, y: frame.maxY)
    }

    /// Sætter vinduets størrelse efter indholdet og flytter det, så logoet bliver stående.
    private func place(resetting: Bool) {
        guard let panel, let hosting = panel.contentView else { return }
        let before = panel.frame
        let size = hosting.fittingSize
        let screen = NSScreen.screens.first { $0.frame.intersects(before) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        var frame = CGRect(origin: .zero, size: size)
        switch model.style {
        case .edge:
            let midY = visible.minY + visible.height * settings.edgeHeight
            frame.origin.x = settings.edgeOnRight ? visible.maxX - size.width : visible.minX
            frame.origin.y = midY - size.height / 2
        default:
            // Logoets hjørne: gemt af brugeren, ellers øverst til højre. Det står stille, mens knapperne folder sig ud.
            let corner = resetting || before.width < 2
                ? (settings.savedOrigin ?? CGPoint(x: visible.maxX - 24, y: visible.maxY - 24))
                : logoCorner(of: before)
            let opensLeft = corner.x > visible.midX
            if opensLeft != model.opensLeft { model.opensLeft = opensLeft } // samme størrelse, knapperne skifter side
            frame.origin.x = opensLeft ? corner.x - size.width : corner.x
            frame.origin.y = corner.y - size.height
        }
        // Hold vinduet inden for skærmen.
        frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - frame.height)
        panel.setFrame(frame, display: true)
    }

    func close() {
        stopTip()
        panel?.orderOut(nil)
        panel = nil
    }
}

/// Indholdet i knapbjælkens vindue.
struct ActionBarHost: View {
    @ObservedObject var model: ActionBarModel
    let onHover: (Bool) -> Void
    let onLogoTap: () -> Void
    let onDrag: (Bool) -> Void
    let onButton: (ActionBarButton) -> Void
    let onButtonHover: (ActionBarButton?) -> Void
    let onListen: () -> Void

    var body: some View {
        content
            .padding(10) // plads til skyggen
            .onHover(perform: onHover)
            .fixedSize()
    }

    @ViewBuilder private var content: some View {
        switch model.style {
        case .edge: edge
        case .floating: VStack(alignment: tipAlignment, spacing: 8) { barWithTip(vertical: true, mark: true) }
        case .hover, .dot: horizontal
        }
    }

    private var tipAlignment: HorizontalAlignment { model.opensLeft ? .trailing : .leading }

    /// Logoet med knapperne ved siden af og forklaringen under.
    private var horizontal: some View {
        VStack(alignment: tipAlignment, spacing: 8) {
            HStack(spacing: 10) {
                if model.opensLeft { buttonsIfShown(vertical: false) }
                logo
                if !model.opensLeft { buttonsIfShown(vertical: false) }
            }
            if let tip = model.tip, model.showsButtons { tipView(tip) }
        }
    }

    /// Fanen i kanten, eller bjælken med forklaringen ved siden af.
    private var edge: some View {
        HStack(alignment: .center, spacing: 8) {
            if !model.edgeOnLeft, let tip = model.tip, model.expanded { tipView(tip) }
            if model.expanded {
                bar(vertical: true, mark: true)
            } else {
                ActionBarEdgeTab()
                    .scaleEffect(x: model.edgeOnLeft ? -1 : 1, y: 1)
                    .onTapGesture(perform: onLogoTap)
                    .gesture(dragGesture)
                    .accessibilityLabel("Baymow-knapper")
                    .accessibilityAddTraits(.isButton)
                    .help("Hold musen her for at se Baymows knapper")
            }
            if model.edgeOnLeft, let tip = model.tip, model.expanded { tipView(tip) }
        }
    }

    @ViewBuilder private func barWithTip(vertical: Bool, mark: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if model.opensLeft, let tip = model.tip { tipView(tip).padding(.top, 50) }
            bar(vertical: vertical, mark: mark)
            if !model.opensLeft, let tip = model.tip { tipView(tip).padding(.top, 50) }
        }
    }

    @ViewBuilder private func buttonsIfShown(vertical: Bool) -> some View {
        if model.showsButtons { bar(vertical: vertical, mark: false) }
    }

    private func bar(vertical: Bool, mark: Bool) -> some View {
        ActionBarView(buttons: model.buttons, vertical: vertical, highlighted: model.tip, showMark: false,
                      action: onButton, onHover: onButtonHover,
                      header: mark ? AnyView(logo) : nil)
    }

    private var logo: some View {
        BaymowMark(size: 42)
            .contentShape(Rectangle())
            .onTapGesture(perform: onLogoTap)
            .gesture(dragGesture)
            .help(model.style == .dot ? "Klik for at vise eller skjule Baymows knapper. Træk for at flytte."
                                      : "Baymow. Træk for at flytte.")
            .accessibilityLabel("Baymow-knapper")
            .accessibilityAddTraits(.isButton)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { _ in onDrag(false) }
            .onEnded { _ in onDrag(true) }
    }

    private func tipView(_ button: ActionBarButton) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(button.help).fixedSize(horizontal: false, vertical: true)
            ListenButton(isPlaying: model.isListening, help: "Læs forklaringen højt", controlSize: .small, action: onListen)
        }
        .padding(10)
        .frame(width: 250, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        .onHover { inside in if inside { onButtonHover(button) } }
    }
}

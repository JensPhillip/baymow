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
    /// Forklaringen, der vises, når musen har stået stille over en knap.
    @Published var tip: ActionBarButton?
    /// Knappen, musen er over.
    @Published var hovered: ActionBarButton?
    /// Knapperne folder sig ud mod venstre (logoet står i højre side af skærmen).
    @Published var opensLeft = true
    /// Ligger bjælken i venstre kant (kun "Fast i skærmens kant").
    @Published var edgeOnLeft = false
    @Published var isListening = false

    /// Står knapperne fremme? "Altid synlig" er altid åben.
    var showsButtons: Bool { style == .floating || expanded }

    func copy() -> ActionBarModel {
        let other = ActionBarModel()
        other.style = style
        other.buttons = buttons
        other.opensLeft = opensLeft
        other.edgeOnLeft = edgeOnLeft
        return other
    }

    /// Til målinger: samme bjælke, åben, med forklaringen fremme.
    func copyWithTip() -> ActionBarModel {
        let other = copy()
        other.expanded = true
        other.tip = tip ?? buttons.first
        return other
    }
}

/// Knapbjælken (AP-77): et lille vindue, der aldrig tager fokus fra det program, brugeren arbejder i. Derfor virker
/// "Læs op" på den tekst, brugeren har markeret – præcis som genvejen.
///
/// Logoet står stille: indholdet er altid tegnet i fuld størrelse og hæftet til logoets hjørne. Lukket er vinduet kun
/// så stort som logoet; ved åbning vokser vinduet først (logoet bliver, hvor det er), og så glider knapperne ind.
/// Ved lukning glider de ud, og først bagefter bliver vinduet lille igen.
@MainActor
final class ActionBarController {
    private let settings: ActionBarSettings
    private let available: () -> Set<ActionBarButton>
    private let perform: (ActionBarButton) -> Void
    private let speak: SpellingPanelModel.Speak
    private let stopSpeaking: () -> Void
    private let model = ActionBarModel()
    /// Til målingen af den fulde størrelse (det rigtige vindue styrer selv sin størrelse).
    static let sizingOptions: NSHostingSizingOptions = [.intrinsicContentSize]
    /// Hvor længe musen skal stå stille over en knap, før forklaringen kommer (brugerens ønske: 3 sekunder).
    static let tipDelay: UInt64 = 3_000_000_000
    static let animation = Animation.spring(response: 0.32, dampingFraction: 0.86)
    private var panel: NSPanel?
    private var cancellables: Set<AnyCancellable> = []
    private var hoverTask: Task<Void, Never>?
    private var tipTask: Task<Void, Never>?
    private var dragStart: (mouse: CGPoint, origin: CGPoint)?
    /// Øges ved hver åbning/lukning, så en sen "gør vinduet lille" ikke rammer en ny åbning.
    private var transition = 0

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
            .sink { [weak self] _ in self?.place() }.store(in: &cancellables)
    }

    /// Viser, skjuler eller opdaterer bjælken ud fra indstillingerne. Kaldes også, når en funktion slås til eller fra.
    func refresh() {
        let buttons = settings.visibleButtons(available: available())
        guard settings.isEnabled, !buttons.isEmpty else {
            close()
            return
        }
        let changed = model.style != settings.style || model.buttons != buttons || model.edgeOnLeft == settings.edgeOnRight
        guard changed || panel == nil else { return }
        if model.style != settings.style { model.expanded = false; model.tip = nil }
        model.style = settings.style
        model.buttons = buttons
        model.edgeOnLeft = !settings.edgeOnRight
        if panel == nil { panel = makePanel() }
        place()
        panel?.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 62, height: 62),
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
        let hosting = NSHostingView(rootView: host(model))
        hosting.sizingOptions = [] // vinduet bestemmer størrelsen; indholdet er hæftet til logoets hjørne
        panel.contentView = hosting
        return panel
    }

    private func host(_ model: ActionBarModel) -> ActionBarHost {
        ActionBarHost(
            model: model,
            onHover: { [weak self] inside in self?.hover(inside) },
            onLogoTap: { [weak self] in self?.logoTapped() },
            onDrag: { [weak self] ended in self?.drag(ended: ended) },
            onButton: { [weak self] button in self?.pressed(button) },
            onButtonHover: { [weak self] button in self?.hoverButton(button) },
            onListen: { [weak self] in self?.listenToTip() })
    }

    // MARK: Mus og klik

    private func hover(_ inside: Bool) {
        hoverTask?.cancel()
        guard model.style == .hover || model.style == .edge, dragStart == nil else { return }
        // Et øjeblik før den folder sig ud (så den ikke springer op, når musen bare kommer forbi), og lidt længere,
        // før den folder sig sammen (så man kan nå at flytte musen hen til knappen).
        let delay: UInt64 = inside ? 300_000_000 : 600_000_000
        hoverTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard let self, !Task.isCancelled, self.model.expanded != inside, self.dragStart == nil else { return }
            self.setExpanded(inside)
        }
    }

    private func logoTapped() {
        guard model.style != .floating else { return }
        hoverTask?.cancel()
        setExpanded(!model.expanded)
    }

    private func pressed(_ button: ActionBarButton) {
        stopTip()
        if model.style != .floating { setExpanded(false) }
        perform(button)
    }

    private func setExpanded(_ expanded: Bool) {
        guard expanded != model.expanded else { return }
        transition += 1
        let current = transition
        if expanded {
            place(full: true) // vinduet vokser først – logoet står stille
            withAnimation(Self.animation) { model.expanded = true }
        } else {
            stopTip()
            withAnimation(Self.animation) { model.expanded = false } completion: { [weak self] in
                guard let self, self.transition == current, !self.model.expanded else { return }
                self.place(full: false) // først når knapperne er væk, bliver vinduet lille
            }
        }
    }

    private func hoverButton(_ button: ActionBarButton?) {
        tipTask?.cancel()
        model.hovered = button
        guard let button else {
            tipTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard let self, !Task.isCancelled, !self.model.isListening else { return }
                withAnimation(.easeOut(duration: 0.15)) { self.model.tip = nil }
            }
            return
        }
        guard model.tip != button else { return }
        tipTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.tipDelay)
            guard let self, !Task.isCancelled, self.model.hovered == button else { return }
            if self.model.isListening { self.stopTip() }
            withAnimation(.easeOut(duration: 0.2)) { self.model.tip = button }
        }
    }

    private func listenToTip() {
        guard let tip = model.tip else { return }
        if model.isListening { stopTip(keepTip: true); return }
        model.isListening = true
        speak(tip.help, .danish) { [weak self] in self?.model.isListening = false }
    }

    private func stopTip(keepTip: Bool = false) {
        tipTask?.cancel()
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
            if (mouse.x > visible.midX) != settings.edgeOnRight {
                settings.edgeOnRight = mouse.x > visible.midX
                model.edgeOnLeft = !settings.edgeOnRight
            }
            origin.x = settings.edgeOnRight ? visible.maxX - panel.frame.width : visible.minX
        }
        panel.setFrameOrigin(origin)
        guard ended else { return }
        dragStart = nil
        if model.style == .edge, let visible = screen?.visibleFrame {
            settings.edgeHeight = min(1, max(0, (panel.frame.midY - visible.minY) / max(visible.height, 1)))
        } else {
            settings.savedOrigin = logoRect(in: panel.frame).origin
        }
        place()
    }

    // MARK: Placering

    /// Logoets plads i vinduets ramme (logoet sidder i det hjørne, knapperne folder sig ud fra).
    private func logoRect(in frame: CGRect) -> CGRect {
        let size = Self.collapsedSize(model)
        return CGRect(x: model.opensLeft ? frame.maxX - size.width : frame.minX, y: frame.maxY - size.height,
                      width: size.width, height: size.height)
    }

    /// Størrelsen med alt foldet ud (knapper og plads til forklaringen).
    static func fullSize(_ model: ActionBarModel) -> CGSize {
        let measure = model.copy()
        measure.expanded = true
        measure.tip = model.tip
        let hosting = NSHostingView(rootView: ActionBarHost(model: measure, onHover: { _ in }, onLogoTap: {}, onDrag: { _ in },
                                                            onButton: { _ in }, onButtonHover: { _ in }, onListen: {},
                                                            measuring: true))
        hosting.sizingOptions = sizingOptions
        return hosting.fittingSize
    }

    /// Størrelsen, når kun logoet (eller fanen i kanten) er synligt.
    static func collapsedSize(_ model: ActionBarModel) -> CGSize {
        switch model.style {
        case .edge:
            let hosting = NSHostingView(rootView: ActionBarEdgeTab().padding(ActionBarHost.insets(model)))
            hosting.sizingOptions = sizingOptions
            return hosting.fittingSize
        case .floating:
            return fullSize(model)
        case .hover, .dot:
            // Logoet står midt for knapperækken (som er højere end logoet), så det lille vindue er rækkens højde.
            let row = NSHostingView(rootView: ActionBarView(buttons: model.buttons, vertical: false, showMark: false))
            row.sizingOptions = sizingOptions
            let height = max(ActionBarHost.logoSize, row.fittingSize.height)
            return CGSize(width: ActionBarHost.logoSize + 2 * ActionBarHost.shadowRoom,
                          height: height + 2 * ActionBarHost.shadowRoom)
        }
    }

    /// Sætter vinduets ramme. `full`: med plads til knapperne (ellers kun logoet). Logoet flytter sig aldrig.
    private func place(full: Bool? = nil) {
        guard let panel else { return }
        let showFull = full ?? model.showsButtons
        let screen = NSScreen.screens.first { $0.frame.intersects(panel.frame) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let collapsed = Self.collapsedSize(model)
        let size = showFull ? Self.fullSize(model) : collapsed

        var frame = CGRect(origin: .zero, size: size)
        switch model.style {
        case .edge:
            let midY = visible.minY + visible.height * settings.edgeHeight
            frame.origin.x = settings.edgeOnRight ? visible.maxX - size.width : visible.minX
            frame.origin.y = min(max(midY - size.height / 2, visible.minY), visible.maxY - size.height)
        case .hover, .dot, .floating:
            // Logoet: gemt af brugeren, ellers øverst til højre. Holdes inden for skærmen.
            var logo = CGRect(origin: settings.savedOrigin ?? CGPoint(x: visible.maxX - collapsed.width - 12,
                                                                       y: visible.maxY - collapsed.height - 12),
                              size: collapsed)
            logo.origin.x = min(max(logo.minX, visible.minX), visible.maxX - logo.width)
            logo.origin.y = min(max(logo.minY, visible.minY), visible.maxY - logo.height)
            let opensLeft = logo.midX > visible.midX
            if opensLeft != model.opensLeft { model.opensLeft = opensLeft }
            frame.origin.x = opensLeft ? logo.maxX - size.width : logo.minX
            frame.origin.y = logo.maxY - size.height
        }
        panel.setFrame(frame, display: true)
    }

    func close() {
        stopTip()
        hoverTask?.cancel()
        model.expanded = false
        panel?.orderOut(nil)
        panel = nil
    }
}

/// Indholdet i knapbjælkens vindue. Altid tegnet i fuld størrelse og hæftet til logoets hjørne, så logoet står stille,
/// uanset hvor stort vinduet er. Forklaringen ligger oven på (påvirker ikke placeringen) i en plads, der er sat af.
struct ActionBarHost: View {
    @ObservedObject var model: ActionBarModel
    let onHover: (Bool) -> Void
    let onLogoTap: () -> Void
    let onDrag: (Bool) -> Void
    let onButton: (ActionBarButton) -> Void
    let onButtonHover: (ActionBarButton?) -> Void
    let onListen: () -> Void

    static let shadowRoom: CGFloat = 10
    static let logoSize: CGFloat = 42
    /// Pladsen, der er sat af til forklaringen (under eller ved siden af knapperne).
    static let tipRoom = CGSize(width: 210, height: 52)

    /// Til målingen af den fulde størrelse: kun indholdet, uden at fylde vinduet ud.
    var measuring = false

    var body: some View {
        if measuring {
            core
        } else {
            // Præcis vinduets størrelse, med indholdet hæftet til logoets hjørne – også når vinduet er mindre end
            // indholdet (lukket). Så står logoet samme sted på skærmen, uanset vinduets størrelse.
            GeometryReader { window in
                core.frame(width: window.size.width, height: window.size.height, alignment: anchor)
            }
            .onHover(perform: onHover)
        }
    }

    private var core: some View {
        content.padding(Self.insets(model)).fixedSize()
    }

    /// Plads til skyggen – men ikke på den side, der rører skærmens kant.
    static func insets(_ model: ActionBarModel) -> EdgeInsets {
        var insets = EdgeInsets(top: shadowRoom, leading: shadowRoom, bottom: shadowRoom, trailing: shadowRoom)
        if model.style == .edge { if model.edgeOnLeft { insets.leading = 0 } else { insets.trailing = 0 } }
        return insets
    }

    /// Hjørnet, logoet (eller fanen) er hæftet til.
    private var anchor: Alignment {
        switch model.style {
        case .edge: return model.edgeOnLeft ? .leading : .trailing
        case .hover, .dot, .floating: return model.opensLeft ? .topTrailing : .topLeading
        }
    }

    @ViewBuilder private var content: some View {
        switch model.style {
        case .hover, .dot: horizontal
        case .edge: edge
        case .floating: floating
        }
    }

    /// Knapperne glider ind fra logoet og toner frem.
    private func revealed<V: View>(_ view: V, from edge: HorizontalEdge) -> some View {
        let shown = model.showsButtons
        return view
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.94, anchor: edge == .trailing ? .trailing : .leading)
            .offset(x: shown ? 0 : (edge == .trailing ? 18 : -18))
            .allowsHitTesting(shown)
            .accessibilityHidden(!shown)
    }

    private var horizontal: some View {
        HStack(spacing: 10) {
            if model.opensLeft { revealed(bar(vertical: false), from: .trailing) }
            logo
            if !model.opensLeft { revealed(bar(vertical: false), from: .leading) }
        }
        .overlay(alignment: model.opensLeft ? .bottomTrailing : .bottomLeading) {
            tipOverlay.alignmentGuide(.bottom) { $0[.top] - 8 } // under knapperne
        }
        .padding(.bottom, Self.tipRoom.height)
    }

    private var edge: some View {
        ZStack(alignment: model.edgeOnLeft ? .leading : .trailing) {
            revealed(bar(vertical: true, header: AnyView(logo)), from: model.edgeOnLeft ? .leading : .trailing)
            ActionBarEdgeTab()
                .scaleEffect(x: model.edgeOnLeft ? -1 : 1, y: 1)
                .opacity(model.expanded ? 0 : 1)
                .onTapGesture(perform: onLogoTap)
                .gesture(dragGesture)
                .allowsHitTesting(!model.expanded)
                .accessibilityLabel("Baymow-knapper")
                .accessibilityAddTraits(.isButton)
        }
        .overlay(alignment: model.edgeOnLeft ? .trailing : .leading) { sideTip(onLeft: !model.edgeOnLeft) }
        .padding(model.edgeOnLeft ? .trailing : .leading, Self.tipRoom.width)
    }

    private var floating: some View {
        bar(vertical: true, header: AnyView(logo))
            .overlay(alignment: model.opensLeft ? .leading : .trailing) { sideTip(onLeft: model.opensLeft) }
            .padding(model.opensLeft ? .leading : .trailing, Self.tipRoom.width)
    }

    /// Forklaringen ved siden af en lodret bjælke.
    private func sideTip(onLeft: Bool) -> some View {
        tipOverlay
            .alignmentGuide(onLeft ? .leading : .trailing) { onLeft ? $0[.trailing] + 8 : $0[.leading] - 8 }
    }

    private func bar(vertical: Bool, header: AnyView? = nil) -> some View {
        ActionBarView(buttons: model.buttons, vertical: vertical, highlighted: model.hovered, showMark: false,
                      action: onButton, onHover: onButtonHover, header: header)
    }

    private var logo: some View {
        BaymowMark(size: Self.logoSize)
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

    @ViewBuilder private var tipOverlay: some View {
        if let tip = model.tip, model.showsButtons {
            ActionBarSmallTip(text: tip.help, isListening: model.isListening, onListen: onListen)
                .frame(width: Self.tipRoom.width - 20)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .onHover { inside in if inside { onButtonHover(tip) } }
        }
    }
}

/// Den lille forklaring: kort tekst og en lille "Hør".
struct ActionBarSmallTip: View {
    let text: String
    let isListening: Bool
    let onListen: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
            Button(action: onListen) {
                Image(systemName: isListening ? "stop.fill" : "speaker.wave.2.fill").font(.system(size: 10, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .background(Color.primary.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .help(isListening ? "Stop" : "Hør forklaringen")
            .accessibilityLabel(isListening ? "Stop" : "Hør")
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.primary.opacity(0.1)))
        .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
    }
}

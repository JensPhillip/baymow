import AppKit
import SwiftUI
import Combine
import BaymowCore

/// Førstegangsopsætningen (AP-41): tre trin fra første start til første oplæsning, uden tekniske ord.
enum OnboardingStep: Int, CaseIterable, Comparable {
    case permission, voice, tryIt, done

    static func < (a: OnboardingStep, b: OnboardingStep) -> Bool { a.rawValue < b.rawValue }

    /// Det trin, brugeren er nået til. Trin, der allerede er klaret (fx adgang givet tidligere), springes over.
    static func current(hasPermission: Bool, hasMainVoice: Bool, skippedVoice: Bool, hasRead: Bool) -> OnboardingStep {
        if !hasPermission { return .permission }
        if !hasMainVoice && !skippedVoice { return .voice }
        if !hasRead { return .tryIt }
        return .done
    }
}

/// Tilstanden bag velkomstvinduet. Følger med i adgang og stemmer af sig selv, og får besked fra `AppShell`,
/// når en oplæsning er startet.
@MainActor
final class OnboardingModel: ObservableObject {
    @Published private(set) var hasPermission = TextCaptureService.hasPermission
    @Published private(set) var hasMainVoice = false
    @Published var skippedVoice = false
    @Published private(set) var hasRead = false

    var step: OnboardingStep {
        OnboardingStep.current(hasPermission: hasPermission, hasMainVoice: hasMainVoice, skippedVoice: skippedVoice, hasRead: hasRead)
    }

    let settings: SettingsStore
    private let catalog: VoiceCatalog
    private let sampleEngine: SpeechEngine
    private var timer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    /// Eksempelteksten i trin 3. Kort, almindelig dansk – ingen tal eller forkortelser.
    static let sampleText = "Velkommen til Baymow. Når du markerer en tekst og trykker på genvejen, bliver teksten læst højt for dig. Det virker i næsten alle programmer på din Mac."

    init(settings: SettingsStore, catalog: VoiceCatalog, sampleEngine: SpeechEngine) {
        self.settings = settings
        self.catalog = catalog
        self.sampleEngine = sampleEngine
        hasMainVoice = !VoiceLibrary.needsMainVoiceGuide(installed: catalog.voices)
        catalog.$voices.sink { [weak self] voices in
            self?.hasMainVoice = !VoiceLibrary.needsMainVoiceGuide(installed: voices)
        }.store(in: &cancellables)
    }

    /// Kaldes, når vinduet vises: adgangen tjekkes jævnligt, så trin 1 klares af sig selv.
    func startWatching() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stopWatching() {
        timer?.invalidate()
        timer = nil
        sampleEngine.stop()
    }

    private func refresh() {
        let trusted = TextCaptureService.hasPermission
        if trusted != hasPermission { hasPermission = trusted }
        catalog.refresh()
    }

    /// `AppShell` melder, at en oplæsning er startet – så har brugeren prøvet genvejen.
    func readingStarted() { hasRead = true }

    func requestPermission() {
        TextCaptureService.requestPermission()
        TextCaptureService.openAccessibilitySettings()
    }

    func playVoiceSample() {
        // Prøven bruger Apples motor; er en anden motors stemme valgt, høres Apples bedste danske stemme.
        let voices = catalog.voices(for: .danish).filter { $0.engineID == sampleEngine.engineID }
        guard let voice = voices.first(where: { $0.id == VoiceLibrary.mainDanishVoiceID }) ?? voices.first else { return }
        sampleEngine.stop()
        sampleEngine.speak(DanishTextNormalizer.normalize(Language.danish.sampleText), voice: voice, rate: settings.rate) { _ in }
    }

    func finish() {
        settings.hasCompletedOnboarding = true
    }
}

// MARK: - Visning

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject var settings: SettingsStore
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Velkommen til Baymow").font(.largeTitle.weight(.semibold))
                Text("Baymow læser tekst højt for dig. Tre små trin, så er du i gang.")
                    .font(.title3).foregroundStyle(.secondary)
            }

            StepCard(number: 1, title: "Giv Baymow lov til at læse det, du markerer",
                     state: state(for: .permission)) {
                Text("Baymow skal have lov til at se den tekst, du markerer. Teksten bliver på din Mac og gemmes ikke.")
                Text("Tryk på knappen. Find Baymow på listen, og slå kontakten til. Måske skal du skrive din adgangskode.")
                Button("Giv lov…") { model.requestPermission() }
                    .buttonStyle(.borderedProminent)
            }

            StepCard(number: 2, title: "Hent den gode danske stemme",
                     state: state(for: .voice)) {
                if model.hasMainVoice {
                    Text("Stemmen Sara (forbedret) er klar.")
                    Button("Hør stemmen") { model.playVoiceSample() }
                } else {
                    Text("Baymow læser dansk bedst med stemmen Sara (forbedret). Den er gratis, men skal hentes én gang.")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("1. Tryk på knappen nedenfor.")
                        Text("2. Ud for Systemstemme: vælg Administrer stemmer… nederst i menuen.")
                        Text("3. Find Dansk, og tryk på pilen ud for Sara (forbedret).")
                        Text("4. Kom tilbage hertil. Baymow opdager selv, når stemmen er hentet.")
                    }
                    HStack {
                        Button("Åbn Systemindstillinger") { VoiceLibrary.openVoiceSettings() }
                            .buttonStyle(.borderedProminent)
                        Button("Spring over") { model.skippedVoice = true }
                            .help("Baymow bruger så en enklere stemme. Du kan hente den gode stemme senere.")
                    }
                }
            }

            StepCard(number: 3, title: "Prøv det",
                     state: state(for: .tryIt)) {
                Text("Markér teksten i feltet med musen. Tryk så på \(settings.shortcut.displayString) – det vil sige \(spokenShortcut) på samme tid.")
                SelectableText(text: OnboardingModel.sampleText)
                    .frame(height: 70)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.4)))
                if model.hasRead {
                    Label("Det virkede! Det samme gør du i alle andre programmer.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            HStack {
                Text("Du kan altid finde Baymow i menulinjen øverst til højre.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button(model.step == .done ? "Færdig" : "Luk") {
                    if model.step == .done { model.finish() }
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            }
        }
        .padding(28)
        .frame(width: 600)
        .onAppear { model.startWatching() }
        .onDisappear { model.stopWatching() }
    }

    /// Genvejen med ord: "Control, Option og S".
    private var spokenShortcut: String {
        let flags = NSEvent.ModifierFlags(rawValue: settings.shortcut.modifiers)
        var keys: [String] = []
        if flags.contains(.control) { keys.append("Control") }
        if flags.contains(.option) { keys.append("Option") }
        if flags.contains(.shift) { keys.append("Skift") }
        if flags.contains(.command) { keys.append("Kommando") }
        keys.append(settings.shortcut.keyLabel)
        return keys.dropLast().joined(separator: ", ") + " og " + keys.last!
    }

    private func state(for step: OnboardingStep) -> StepCard<EmptyView>.State {
        if step == .voice && model.skippedVoice && !model.hasMainVoice { return .skipped }
        if model.step > step { return .done }
        return model.step == step ? .active : .waiting
    }
}

private struct StepCard<Content: View>: View {
    enum State { case waiting, active, done, skipped }

    let number: Int
    let title: String
    let state: StepCard<EmptyView>.State
    @ViewBuilder let content: () -> Content

    init(number: Int, title: String, state: StepCard<EmptyView>.State, @ViewBuilder content: @escaping () -> Content) {
        self.number = number
        self.title = title
        self.state = state
        self.content = content
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(badgeColor).frame(width: 30, height: 30)
                if state == .done {
                    Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title).font(.title3.weight(.semibold))
                    if state == .done { Text("Klaret").font(.callout).foregroundStyle(.green) }
                    if state == .skipped { Text("Sprunget over").font(.callout).foregroundStyle(.secondary) }
                }
                if state == .active {
                    VStack(alignment: .leading, spacing: 8, content: content)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .opacity(state == .waiting ? 0.5 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Trin \(number): \(title)\(state == .done ? ", klaret" : "")")
    }

    private var badgeColor: Color {
        switch state {
        case .done: return .green
        case .active: return .accentColor
        case .waiting, .skipped: return .secondary
        }
    }
}

/// Tekst, der kan markeres, men ikke ændres. Bygger på et rigtigt tekstfelt, så både Tilgængelighed og ⌘C
/// kan hente markeringen – præcis som i andre programmer.
private struct SelectableText: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let view = scroll.documentView as! NSTextView
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.font = .systemFont(ofSize: 15)
        view.textContainerInset = NSSize(width: 6, height: 6)
        view.string = text
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        return scroll
    }

    func updateNSView(_ view: NSScrollView, context: Context) {}
}

/// Velkomstvinduet. Vises ved første start og fra menuen "Kom i gang…".
@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?
    let model: OnboardingModel

    init(model: OnboardingModel) { self.model = model }

    func show() {
        if window == nil {
            let view = OnboardingView(model: model, settings: model.settings) { [weak self] in self?.window?.close() }
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 640),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Kom i gang med Baymow"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: view)
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Markeret tekst i Baymows eget vindue (fx eksempelteksten i "Prøv det"). Programmers almindelige vej –
/// Tilgængelighed og ⌘C – virker ikke, når Baymow selv er forrest, så teksten læses direkte fra tekstfeltet.
@MainActor
enum OwnWindowSelection {
    static func text() -> String? {
        guard NSApp.isActive, let view = NSApp.keyWindow?.firstResponder as? NSTextView else { return nil }
        let range = view.selectedRange()
        guard range.location != NSNotFound, range.length > 0 else { return nil }
        let selected = (view.string as NSString).substring(with: range)
        return selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : selected
    }
}

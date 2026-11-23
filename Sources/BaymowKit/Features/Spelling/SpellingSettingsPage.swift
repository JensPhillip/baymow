import AppKit
import SwiftUI
import BaymowCore

/// Siden "Stavning" i hovedvinduet: slå stavehjælpen til, se hvordan den bruges, og om Macens sprogmodel er klar.
struct SpellingSettingsPage: View {
    @ObservedObject var settings: SpellingSettings
    let speak: (String) -> Void
    /// Åbner siden "AI og nøgler" (nøgler og forbrug).
    var openAIPage: () -> Void = {}

    var body: some View {
        Section {
            OptionRow(symbol: "textformat.abc.dottedunderline", color: .teal, title: "Stavehjælp",
                      subtitle: "Ret den tekst, du selv har skrevet.",
                      help: "Markér din egen tekst, og tryk \(settings.shortcut.displayString). Baymow viser rettelserne, og du vælger selv, om de skal bruges.",
                      isOn: $settings.isEnabled)
            if settings.isEnabled, settings.shortcutFailed {
                Label("Tasterne \(settings.shortcut.displayString) bruges af et andet program.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .onAppear { settings.refreshModelStatus(); settings.ai.refreshKeys() }

        // Slået fra: kun kontakten, så siden ikke forvirrer (brugerens ønske 23. november 2026).
        if settings.isEnabled { details }
    }

    @ViewBuilder private var details: some View {
        Section("Sådan gør du") {
            GuideStep(number: 1, symbol: "character.cursor.ibeam", text: "Markér det, du har skrevet")
            HStack(spacing: 10) {
                Text("2").font(.caption.weight(.bold)).foregroundStyle(.white)
                    .frame(width: 20, height: 20).background(Color.accentColor, in: Circle())
                Image(systemName: "keyboard").foregroundStyle(.secondary).frame(width: 20)
                Text("Tryk")
                KeyCaps(shortcut: settings.shortcut, size: 26)
            }
            .accessibilityElement(children: .combine)
            GuideStep(number: 3, symbol: "hand.tap", text: "Tryk på et ord for at vælge det og høre det")
            GuideStep(number: 4, symbol: "checkmark.circle", text: "Tryk på \"Brug rettelsen\"")
        }

        Section("Farverne") {
            ColorRow(color: SpellingPanelView.corrected, symbol: "checkmark.circle.fill", text: "Grøn: rettet af Baymow")
            ColorRow(color: SpellingPanelView.uncertain, symbol: "questionmark.circle.fill", text: "Orange: tjek selv")
        }

        Section("Hvor meget skal Baymow rette?") {
            LevelPicker(settings: settings)
        }

        Section {
            modelStatus
            if !settings.cloudEnabled {
                Label("Din tekst bliver på din Mac. Intet sendes væk.", systemImage: "lock.fill")
                    .foregroundStyle(.secondary)
            }
        }

        Section {
            OptionRow(symbol: "cloud.fill", color: .blue, title: "Bedre hjælp via internet",
                      subtitle: "Finder flere fejl, også rigtige ord brugt forkert.",
                      help: "Claude eller ChatGPT retter din tekst. Det kræver internet og din egen nøgle fra firmaet. Uden internet bruger Baymow Macens egen hjælp.",
                      isOn: $settings.cloudEnabled)
            if settings.cloudEnabled {
                FeatureAIChoice(ai: settings.ai, feature: .spelling, provider: $settings.cloudProvider, openAIPage: openAIPage)
                Label("Når du trykker \(settings.shortcut.displayString), sendes den markerede tekst til \(settings.cloudProvider.company). Uden internet bruger Baymow Macens egen hjælp.",
                      systemImage: "paperplane.fill")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var modelStatus: some View {
        switch settings.modelStatus {
        case .ready:
            Label("Macens egen sprogmodel er klar", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .appleIntelligenceOff:
            HStack {
                Label("Slå Apple Intelligence til for den bedste hjælp", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                Spacer()
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                } label: { Label("Åbn", systemImage: "gearshape") }
                .help("Åbner Systemindstillinger. Uden Apple Intelligence bruger Baymow kun Macens stavekontrol.")
            }
        case .notReady:
            Label("Macen henter sin sprogmodel. Prøv igen om lidt.", systemImage: "arrow.down.circle")
                .foregroundStyle(.secondary)
        case .notSupported:
            Label("Kun Macens stavekontrol (denne Mac har ikke Apple Intelligence)", systemImage: "info.circle")
                .foregroundStyle(.secondary)
        }
    }
}

private struct ColorRow: View {
    let color: Color
    let symbol: String
    let text: String

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol).foregroundStyle(color)
        }
    }
}

/// Tre niveauer med billede og én linje hver. "Klarere sætninger" kræver hjælp via internet og er aldrig standard.
private struct LevelPicker: View {
    @ObservedObject var settings: SpellingSettings

    var body: some View {
        ForEach(SpellingLevel.allCases) { level in
            let available = level != .clarity || settings.cloudEnabled
            Button { settings.level = level } label: {
                HStack(spacing: 12) {
                    Image(systemName: settings.level == level ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 18)).foregroundStyle(settings.level == level ? Color.accentColor : .secondary)
                    IconTile(symbol: Self.symbol(level), color: .teal, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(Self.title(level)).font(.headline)
                            if level == .standard { Badge(text: "Anbefalet", symbol: "star.fill", color: .green) }
                        }
                        Text(Self.subtitle(level)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!available)
            .opacity(available ? 1 : 0.5)
            .accessibilityAddTraits(settings.level == level ? .isSelected : [])
            .help(available ? Self.subtitle(level) : "Kræver \"Bedre hjælp via internet\".")
        }
        if settings.level == .clarity, !settings.cloudEnabled {
            Label("Klarere sætninger kræver hjælp via internet. Indtil da retter Baymow stavning og tegnsætning.",
                  systemImage: "info.circle")
                .foregroundStyle(.orange)
        } else if settings.level == .clarity {
            Label("Baymow kender ikke hele sammenhængen. Læs forslagene, før du bruger dem: du kan altid vælge dine egne ord.",
                  systemImage: "exclamationmark.bubble")
                .foregroundStyle(.secondary)
        }
    }

    static func title(_ level: SpellingLevel) -> String {
        switch level {
        case .spelling: return "Kun stavning"
        case .punctuation: return "Stavning og tegnsætning"
        case .clarity: return "Også klarere sætninger"
        }
    }

    static func subtitle(_ level: SpellingLevel) -> String {
        switch level {
        case .spelling: return "Retter stavefejl. Kommaer og punktum er dine egne."
        case .punctuation: return "Retter også kommaer, punktum og store bogstaver."
        case .clarity: return "Gør også tunge sætninger kortere og lettere at forstå. Kræver hjælp via internet."
        }
    }

    static func symbol(_ level: SpellingLevel) -> String {
        switch level {
        case .spelling: return "textformat.abc"
        case .punctuation: return "textformat.abc.dottedunderline"
        case .clarity: return "text.badge.star"
        }
    }
}

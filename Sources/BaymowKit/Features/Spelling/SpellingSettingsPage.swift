import AppKit
import SwiftUI
import BaymowCore

/// Siden "Stavning" i hovedvinduet: slå stavehjælpen til, se hvordan den bruges, og om Macens sprogmodel er klar.
struct SpellingSettingsPage: View {
    @ObservedObject var settings: SpellingSettings
    let speak: (String) -> Void

    var body: some View {
        Section {
            OptionRow(symbol: "textformat.abc.dottedunderline", color: .teal, title: "Stavehjælp",
                      subtitle: "Ret den tekst, du selv har skrevet.",
                      help: "Markér din egen tekst, og tryk \(SpellingSettings.shortcut.displayString). Baymow viser rettelserne, og du vælger selv, om de skal bruges.",
                      isOn: $settings.isEnabled)
            if settings.isEnabled, settings.shortcutFailed {
                Label("Tasterne \(SpellingSettings.shortcut.displayString) bruges af et andet program.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }

        Section("Sådan gør du") {
            GuideStep(number: 1, symbol: "character.cursor.ibeam", text: "Markér det, du har skrevet")
            HStack(spacing: 10) {
                Text("2").font(.caption.weight(.bold)).foregroundStyle(.white)
                    .frame(width: 20, height: 20).background(Color.accentColor, in: Circle())
                Image(systemName: "keyboard").foregroundStyle(.secondary).frame(width: 20)
                Text("Tryk")
                KeyCaps(shortcut: SpellingSettings.shortcut, size: 26)
            }
            .accessibilityElement(children: .combine)
            GuideStep(number: 3, symbol: "hand.tap", text: "Tryk på et ord for at vælge det og høre det")
            GuideStep(number: 4, symbol: "checkmark.circle", text: "Tryk på \"Brug rettelsen\"")
        }

        Section("Farverne") {
            ColorRow(color: SpellingPanelView.corrected, symbol: "checkmark.circle.fill", text: "Grøn: rettet af Baymow")
            ColorRow(color: SpellingPanelView.uncertain, symbol: "questionmark.circle.fill", text: "Orange: tjek selv")
        }

        Section {
            modelStatus
            Label("Din tekst bliver på din Mac. Intet sendes væk.", systemImage: "lock.fill")
                .foregroundStyle(.secondary)
        }
        .onAppear { settings.refreshModelStatus() }
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

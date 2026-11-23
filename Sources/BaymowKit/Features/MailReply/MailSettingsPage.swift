import SwiftUI
import BaymowCore

/// Siden "Mail" i hovedvinduet: slå mail-svar til, se hvordan, vælg tone og firma.
struct MailSettingsPage: View {
    @ObservedObject var settings: MailReplySettings
    @ObservedObject var ai: AIServices
    /// Åbner siden "AI og nøgler".
    var openAIPage: () -> Void = {}

    var body: some View {
        Section {
            OptionRow(symbol: "envelope.fill", color: .indigo, title: "Mail-svar",
                      subtitle: "Få et forslag til svar ud fra mailtråden.",
                      help: "Skriv stikord øverst i dit svar, og tryk \(settings.shortcut.displayString). Baymow skriver svaret og sætter det ind i stedet for stikordene.",
                      isOn: $settings.isEnabled)
            if settings.isEnabled, settings.shortcutFailed {
                Label("Tasterne \(settings.shortcut.displayString) bruges af et andet program.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
        if settings.isEnabled { details }

        Section {
            OptionRow(symbol: "bubble.left.and.text.bubble.right.fill", color: .indigo, title: "Sparring om mailen",
                      subtitle: "Stil spørgsmål til den mail, du har åben.",
                      help: "Åbn en mail i Apple Mail, og tryk \(settings.sparringShortcut.displayString). Spørg fx, hvad afsenderen vil, eller hvad du bør svare.",
                      isOn: $settings.sparringEnabled)
            if settings.sparringEnabled {
                GuideStep(number: 1, symbol: "envelope.open.fill", text: "Åbn mailen i Apple Mail")
                HStack(spacing: 10) {
                    Text("2").font(.caption.weight(.bold)).foregroundStyle(.white)
                        .frame(width: 20, height: 20).background(Color.accentColor, in: Circle())
                    Image(systemName: "keyboard").foregroundStyle(.secondary).frame(width: 20)
                    Text("Tryk")
                    KeyCaps(shortcut: settings.sparringShortcut, size: 26)
                }
                .accessibilityElement(children: .combine)
                GuideStep(number: 3, symbol: "questionmark.bubble", text: "Tryk på et spørgsmål, eller skriv dit eget")
                if settings.sparringShortcutFailed {
                    Label("Tasterne \(settings.sparringShortcut.displayString) bruges af et andet program.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                Label("Intet sendes, før du stiller et spørgsmål. Så sendes mailen til \(settings.provider.company).",
                      systemImage: "paperplane.fill")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }

        if settings.sparringEnabled && !settings.isEnabled {
            Section("Hvem svarer") {
                FeatureAIChoice(ai: ai, feature: .mail, provider: $settings.provider, openAIPage: openAIPage)
            }
        }
    }

    @ViewBuilder private var details: some View {
        Section("Sådan gør du") {
            GuideStep(number: 1, symbol: "arrowshape.turn.up.left.fill", text: "Tryk Svar i Apple Mail")
            GuideStep(number: 2, symbol: "list.bullet", text: "Skriv stikord øverst – eller ingenting")
            HStack(spacing: 10) {
                Text("3").font(.caption.weight(.bold)).foregroundStyle(.white)
                    .frame(width: 20, height: 20).background(Color.accentColor, in: Circle())
                Image(systemName: "keyboard").foregroundStyle(.secondary).frame(width: 20)
                Text("Tryk")
                KeyCaps(shortcut: settings.shortcut, size: 26)
                Text("med markøren lige efter stikordene").foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            GuideStep(number: 4, symbol: "exclamationmark.bubble", text: "Udfyld felterne i [klammer], og læs svaret igennem")
        }

        Section("Om dig") {
            HStack(spacing: 10) {
                Image(systemName: "person.fill").foregroundStyle(.secondary).frame(width: 20)
                TextField("Dit navn", text: $settings.yourName, prompt: Text("Dit navn"))
                    .textFieldStyle(.roundedBorder)
            }
            Text("Så kan Baymow se, når den nyeste mail er din egen, og skrive en opfølgning i stedet for at svare dig selv.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Toggle(isOn: $settings.hasStandardSignature) {
                Label("Jeg har en fast signatur i mailprogrammet", systemImage: "signature")
            }
            .help("Så skriver Baymow aldrig hilsen eller navn til sidst i svaret.")
        }

        Section("Tone") {
            HStack(spacing: 10) {
                Image(systemName: "text.bubble").foregroundStyle(.secondary).frame(width: 20)
                TextField("Tone", text: $settings.tone, prompt: Text(MailReplySettings.standardTone))
                    .textFieldStyle(.roundedBorder)
            }
            Text("Fx \"Menneskelig og formel\" eller \"Kort og venlig, du-form\". Baymow opdigter aldrig aftaler, datoer eller priser: mangler noget, står der [et felt], du udfylder.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }

        Section("Hvem skriver svaret") {
            FeatureAIChoice(ai: ai, feature: .mail, provider: $settings.provider, openAIPage: openAIPage)
            Label("Når du trykker \(settings.shortcut.displayString), sendes dine stikord og den citerede mailtråd til \(settings.provider.company). Der kan stå andre menneskers oplysninger i tråden.",
                  systemImage: "paperplane.fill")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { ai.refreshKeys() }
    }
}

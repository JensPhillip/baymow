import SwiftUI
import BaymowCore

/// Siden "Mail" i hovedvinduet: slå mail-svar til, se hvordan, vælg tone og firma.
struct MailSettingsPage: View {
    @ObservedObject var settings: MailReplySettings
    @ObservedObject var cloud: SpellingSettings

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
            CloudSettings(settings: cloud, showsSpellingNote: false)
            Label("Når du trykker \(settings.shortcut.displayString), sendes dine stikord og den citerede mailtråd til \(cloud.cloudProvider.company). Der kan stå andre menneskers oplysninger i tråden.",
                  systemImage: "paperplane.fill")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { cloud.refreshKeys() }
    }
}

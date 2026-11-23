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
            if !settings.cloudEnabled {
                Label("Din tekst bliver på din Mac. Intet sendes væk.", systemImage: "lock.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { settings.refreshModelStatus(); settings.refreshKeys() }

        Section {
            OptionRow(symbol: "cloud.fill", color: .blue, title: "Bedre hjælp via internet",
                      subtitle: "Finder flere fejl, også rigtige ord brugt forkert.",
                      help: "Claude eller ChatGPT retter din tekst. Det kræver internet og din egen nøgle fra firmaet. Uden internet bruger Baymow Macens egen hjælp.",
                      isOn: $settings.cloudEnabled)
            if settings.cloudEnabled { CloudSettings(settings: settings) }
        }

        if settings.cloudEnabled {
            Section("Forbrug") { UsageView(usage: settings.usage) }
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

/// Vælg firma, gem nøglen, og prøv om den virker.
private struct CloudSettings: View {
    @ObservedObject var settings: SpellingSettings
    @State private var newKey = ""

    var body: some View {
        Picker("Firma", selection: $settings.cloudProvider) {
            ForEach(CloudProvider.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)

        let provider = settings.cloudProvider
        if settings.savedKeys.contains(provider) {
            HStack(spacing: 10) {
                Label("Nøgle til \(provider.title) er gemt", systemImage: "key.fill").foregroundStyle(.green)
                Spacer()
                Button { settings.testConnection() } label: { Label("Prøv", systemImage: "bolt.horizontal.circle") }
                    .help("Sender en fast testsætning til \(provider.company) – ikke din tekst.")
                Button(role: .destructive) { settings.deleteKey() } label: { Label("Slet", systemImage: "trash") }
                    .help("Fjerner nøglen fra Macens nøglering.")
            }
            testStatus
        } else {
            HStack(spacing: 10) {
                Image(systemName: "key").foregroundStyle(.secondary).frame(width: 20)
                Text("Din nøgle fra \(provider.keySite)").fixedSize()
                SecureField("Nøgle", text: $newKey, prompt: Text("Indsæt nøglen her"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                Button("Gem", action: save).disabled(newKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Label("Nøglen gemmes i Macens nøglering og vises ikke igen.", systemImage: "lock.fill")
                .font(.callout).foregroundStyle(.secondary)
        }

        Label("Når du trykker \(SpellingSettings.shortcut.displayString), sendes den markerede tekst til \(provider.company). Uden internet bruger Baymow Macens egen hjælp.",
              systemImage: "paperplane.fill")
            .foregroundStyle(.secondary)
    }

    @ViewBuilder private var testStatus: some View {
        switch settings.testResult {
        case nil: EmptyView()
        case .testing:
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Prøver forbindelsen …").foregroundStyle(.secondary) }
        case .ok:
            Label("Det virker", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let problem):
            Label(Self.message(problem, settings.cloudProvider), systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    static func message(_ problem: CloudSpellingError, _ provider: CloudProvider) -> String {
        switch problem {
        case .badKey: return "\(provider.company) afviser nøglen. Lav en ny på \(provider.keySite), og gem den igen."
        case .offline: return "Intet internet lige nu."
        case .noKey: return "Der er ingen nøgle gemt."
        case .failed: return "\(provider.title) svarede ikke. Tjek, at der er penge på kontoen hos \(provider.company)."
        }
    }

    private func save() {
        let key = newKey
        newKey = ""
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        settings.saveKey(key)
        settings.testConnection()
    }
}

/// Forbruget denne måned pr. firma, og tidligere måneder. Et skøn ud fra priserne; kun tal er gemt.
private struct UsageView: View {
    @ObservedObject var usage: CloudUsageLog
    @State private var showEarlier = false
    @State private var confirmReset = false

    var body: some View {
        Text(CloudUsageLog.monthName(usage.currentMonth).capitalized).font(.headline)
        ForEach(CloudProvider.allCases) { provider in row(provider, month: usage.currentMonth) }

        if !usage.earlierMonths.isEmpty {
            DisclosureGroup("Tidligere måneder", isExpanded: $showEarlier) {
                ForEach(usage.earlierMonths, id: \.self) { month in
                    Text(CloudUsageLog.monthName(month).capitalized).font(.subheadline.weight(.semibold)).padding(.top, 4)
                    ForEach(CloudProvider.allCases) { provider in
                        if usage.entry(provider, month: month).checks > 0 { row(provider, month: month) }
                    }
                }
            }
        }

        HStack(alignment: .top) {
            Label("Et skøn ud fra priserne \(CloudPricing.checked) og en kurs på \(Self.kroner(CloudPricing.kronerPerDollar, decimals: 2)) pr. dollar. Den præcise regning står hos OpenAI og Anthropic.",
                  systemImage: "info.circle")
                .font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button("Nulstil") { confirmReset = true }
                .help("Sætter tallene på 0. Det ændrer ikke din regning hos firmaerne.")
                .confirmationDialog("Nulstil forbruget?", isPresented: $confirmReset) {
                    Button("Nulstil", role: .destructive) { usage.reset() }
                } message: { Text("Tallene i Baymow sættes på 0. Det ændrer ikke din regning hos firmaerne.") }
        }
    }

    private func row(_ provider: CloudProvider, month: String) -> some View {
        let entry = usage.entry(provider, month: month)
        return HStack(spacing: 10) {
            Image(systemName: "cloud.fill").foregroundStyle(.blue).frame(width: 20)
            Text(provider.title)
            Spacer()
            Text(entry.checks == 1 ? "1 kontrol" : "\(entry.checks) kontroller").foregroundStyle(.secondary).monospacedDigit()
            Text("ca. " + Self.kroner(usage.kroner(provider, month: month), decimals: 2))
                .monospacedDigit().frame(minWidth: 90, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .help("\(entry.inputTokens) tokens sendt, \(entry.outputTokens) tokens i svar")
    }

    /// "0,35 kr." – med dansk komma.
    static func kroner(_ value: Double, decimals: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "da_DK")
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        return (formatter.string(from: NSNumber(value: value)) ?? "\(value)") + " kr."
    }
}

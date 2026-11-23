import AppKit
import SwiftUI
import Charts
import BaymowCore

/// Siden "AI og nøgler" (AP-72): nøglerne til ChatGPT og Claude, hvilket firma hver funktion bruger, og forbruget
/// pr. funktion. Nøgler og forbrug administreres ét sted; firmaet vælges pr. funktion.
struct AISettingsPage: View {
    @ObservedObject var ai: AIServices
    @ObservedObject var spelling: SpellingSettings
    @ObservedObject var mail: MailReplySettings

    var body: some View {
        Section("Nøgler") {
            ForEach(CloudProvider.allCases) { provider in KeyRow(ai: ai, provider: provider) }
            Label("Nøglerne gemmes i Macens nøglering og vises ikke igen. Du betaler selv firmaerne for forbruget.",
                  systemImage: "lock.fill")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { ai.refreshKeys() }

        Section("Hvem bruges til hvad") {
            FeatureRow(feature: .spelling, isOn: spelling.cloudEnabled, provider: $spelling.cloudProvider, ai: ai,
                       offText: "Bedre hjælp via internet er slået fra (siden Stavning).")
            FeatureRow(feature: .mail, isOn: mail.isEnabled, provider: $mail.provider, ai: ai,
                       offText: "Mail-svar er slået fra (siden Mail).")
        }

        Section("Forbrug") { UsageView(usage: ai.usage) }
    }
}

/// Én funktion: hvilket firma den bruger, og om nøglen findes.
private struct FeatureRow: View {
    let feature: AIFeature
    let isOn: Bool
    @Binding var provider: CloudProvider
    @ObservedObject var ai: AIServices
    let offText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                IconTile(symbol: feature.symbol, color: feature == .spelling ? .teal : .indigo, size: 30)
                Text(feature.title).font(.headline)
                Spacer()
                Picker(feature.title, selection: $provider) {
                    ForEach(CloudProvider.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            if !isOn {
                Text(offText).font(.callout).foregroundStyle(.secondary)
            } else if !ai.savedKeys.contains(provider) {
                Label("Der mangler en nøgle til \(provider.title).", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Én nøgle: gemt (Prøv/Slet) eller et felt til at indsætte den.
struct KeyRow: View {
    @ObservedObject var ai: AIServices
    let provider: CloudProvider
    @State private var newKey = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if ai.savedKeys.contains(provider) {
                HStack(spacing: 10) {
                    Label("\(provider.title): nøgle gemt", systemImage: "key.fill").foregroundStyle(.green)
                    Spacer()
                    Button { ai.testConnection(provider) } label: { Label("Prøv", systemImage: "bolt.horizontal.circle") }
                        .help("Sender en fast testsætning til \(provider.company) – ikke din tekst.")
                    Button(role: .destructive) { ai.deleteKey(for: provider) } label: { Label("Slet", systemImage: "trash") }
                        .help("Fjerner nøglen fra Macens nøglering.")
                }
                status
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "key").foregroundStyle(.secondary).frame(width: 20)
                    Text("\(provider.title) (\(provider.keySite))").fixedSize()
                    SecureField("Nøgle", text: $newKey, prompt: Text("Indsæt nøglen her"))
                        .labelsHidden().textFieldStyle(.roundedBorder).onSubmit(save)
                    Button("Gem", action: save).disabled(newKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    @ViewBuilder private var status: some View {
        switch ai.testResults[provider] {
        case nil: EmptyView()
        case .testing:
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Prøver forbindelsen …").foregroundStyle(.secondary) }
        case .ok:
            Label("Det virker", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let problem):
            Label(Self.message(problem, provider), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
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
        ai.saveKey(key, for: provider)
        ai.testConnection(provider)
    }
}

/// På siderne Stavning og Mail: vælg firma, se om nøglen findes, og se månedens forbrug med et link til det hele.
struct FeatureAIChoice: View {
    @ObservedObject var ai: AIServices
    @ObservedObject var usage: CloudUsageLog
    let feature: AIFeature
    @Binding var provider: CloudProvider
    let openAIPage: () -> Void

    init(ai: AIServices, feature: AIFeature, provider: Binding<CloudProvider>, openAIPage: @escaping () -> Void) {
        self.ai = ai
        self.usage = ai.usage
        self.feature = feature
        _provider = provider
        self.openAIPage = openAIPage
    }

    var body: some View {
        Picker("Firma", selection: $provider) {
            ForEach(CloudProvider.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)

        if ai.savedKeys.contains(provider) {
            Label("Nøgle til \(provider.title) er gemt", systemImage: "key.fill").foregroundStyle(.green)
        } else {
            HStack {
                Label("Der mangler en nøgle til \(provider.title).", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Spacer()
                Button(action: openAIPage) { Label("Gem nøgle", systemImage: "key") }
            }
        }

        let entry = usage.entry(feature: feature)
        HStack {
            Label("\(CloudUsageLog.monthName(usage.currentMonth).capitalized): \(entry.checks == 1 ? "1 gang" : "\(entry.checks) gange") · ca. \(UsageView.kroner(usage.kroner(feature: feature), decimals: 4))",
                  systemImage: "chart.bar.fill")
                .foregroundStyle(.secondary).monospacedDigit()
            Spacer()
            Button(action: openAIPage) { Label("Se forbrug og nøgler", systemImage: "arrow.right") }
                .help("Åbner siden AI og nøgler")
        }
    }
}

// MARK: Forbrug

/// Forbruget denne måned pr. funktion, tidligere måneder og en graf over tid. Et skøn ud fra priserne; kun tal er gemt.
struct UsageView: View {
    @ObservedObject var usage: CloudUsageLog
    @State private var showEarlier = false
    /// Grafen er lukket, til brugeren selv åbner den.
    @State private var showChart: Bool
    @State private var measure: UsageChart.Measure = .price

    /// `showChart` kun til skærmbilleder.
    init(usage: CloudUsageLog, showChart: Bool = false) {
        self.usage = usage
        _showChart = State(initialValue: showChart)
    }

    var body: some View {
        Text(CloudUsageLog.monthName(usage.currentMonth).capitalized).font(.headline)
        ForEach(AIFeature.allCases) { feature in row(feature, month: usage.currentMonth) }
        totalRow(month: usage.currentMonth)

        if !usage.earlierMonths.isEmpty {
            DisclosureGroup("Tidligere måneder", isExpanded: $showEarlier) {
                ForEach(usage.earlierMonths, id: \.self) { month in
                    Text(CloudUsageLog.monthName(month).capitalized).font(.subheadline.weight(.semibold)).padding(.top, 4)
                    ForEach(AIFeature.allCases) { feature in
                        if usage.entry(feature: feature, month: month).checks > 0 { row(feature, month: month) }
                    }
                    totalRow(month: month)
                }
            }
        }

        DisclosureGroup(isExpanded: $showChart) {
            UsageChart(usage: usage, measure: measure)
        } label: {
            // "Pris"/"Kontroller" står på samme linje, når grafen er åben: det sparer plads.
            HStack {
                Text("Vis graf over tid")
                Spacer()
                if showChart {
                    Picker("Vis", selection: $measure) {
                        ForEach(UsageChart.Measure.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
            }
        }

        UsageFootnote(usage: usage)
    }

    private func row(_ feature: AIFeature, month: String) -> some View {
        let entry = usage.entry(feature: feature, month: month)
        let providers = usage.providers(for: feature, month: month).map(\.title).joined(separator: " og ")
        return HStack(spacing: 10) {
            Image(systemName: feature.symbol).foregroundStyle(UsageChart.color(feature)).frame(width: 20)
            Text(feature.title)
            if !providers.isEmpty { Text(providers).font(.callout).foregroundStyle(.secondary) }
            Spacer()
            Text(entry.checks == 1 ? "1 gang" : "\(entry.checks) gange").foregroundStyle(.secondary).monospacedDigit()
            Text("ca. " + Self.kroner(usage.kroner(feature: feature, month: month), decimals: 4))
                .monospacedDigit().frame(minWidth: 110, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .help("\(entry.inputTokens) tokens sendt, \(entry.outputTokens) tokens i svar")
    }

    private func totalRow(month: String) -> some View {
        HStack {
            Text("I alt").font(.headline)
            Spacer()
            Text("ca. " + Self.kroner(usage.kroner(month: month), decimals: 4)).font(.headline).monospacedDigit()
        }
    }

    /// "0,0110 kr." – med dansk komma.
    static func kroner(_ value: Double, decimals: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "da_DK")
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        return (formatter.string(from: NSNumber(value: value)) ?? "\(value)") + " kr."
    }
}

private struct UsageFootnote: View {
    @ObservedObject var usage: CloudUsageLog
    @State private var confirmReset = false

    var body: some View {
        HStack(alignment: .top) {
            Label("Et skøn ud fra priserne \(CloudPricing.checked) og en kurs på \(UsageView.kroner(CloudPricing.kronerPerDollar, decimals: 2)) pr. dollar. Den præcise regning står hos OpenAI og Anthropic.",
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
}

/// Søjler pr. dag de seneste 30 dage, én funktion pr. farve. Hold musen over en dag for at se tallene.
struct UsageChart: View {
    @ObservedObject var usage: CloudUsageLog
    let measure: Measure
    @State private var selectedDay: Date?

    /// `selectedDay` kun til skærmbilleder (som om musen holdes over dagen).
    init(usage: CloudUsageLog, measure: Measure = .price, selectedDay: Date? = nil) {
        self.usage = usage
        self.measure = measure
        _selectedDay = State(initialValue: selectedDay)
    }

    enum Measure: String, CaseIterable, Identifiable {
        case price = "Pris", checks = "Antal"
        var id: String { rawValue }
    }

    /// Farver fra en palet, der er kontrolleret for farveblindhed (lys og mørk).
    static func color(_ feature: AIFeature) -> Color {
        let (light, dark): (UInt32, UInt32) = feature == .spelling ? (0x2a78d6, 0x3987e5) : (0xeb6834, 0xd95926)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                           blue: CGFloat(hex & 0xff) / 255, alpha: 1)
        })
    }

    var body: some View {
        let points = usage.lastDays(30)
        VStack(alignment: .leading, spacing: 10) {
            Chart {
                ForEach(points) { point in
                    BarMark(x: .value("Dag", point.day, unit: .day), y: .value(measure.rawValue, value(point)))
                        .foregroundStyle(by: .value("Funktion", point.feature.title))
                        .cornerRadius(3)
                }
                if let selectedDay {
                    RuleMark(x: .value("Dag", selectedDay, unit: .day))
                        .foregroundStyle(.secondary.opacity(0.35))
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            tooltip(for: selectedDay, points: points)
                        }
                }
            }
            .chartForegroundStyleScale(domain: AIFeature.allCases.map(\.title), range: AIFeature.allCases.map(Self.color))
            .chartLegend(position: .bottom, alignment: .leading)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                    AxisValueLabel(format: .dateTime.day().month(.twoDigits).locale(Locale(identifier: "da_DK")))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(measure == .price ? UsageView.kroner(number, decimals: axisDecimals(points)) : "\(Int(number))")
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                guard let frame = proxy.plotFrame else { return }
                                if let date: Date = proxy.value(atX: location.x - geometry[frame].origin.x) {
                                    selectedDay = Calendar(identifier: .gregorian).startOfDay(for: date)
                                }
                            case .ended:
                                selectedDay = nil
                            }
                        }
                }
            }
            .frame(height: 200)
            .padding(.top, 34)

            if points.allSatisfy({ $0.entry.checks == 0 && $0.entry.inputTokens == 0 }) {
                Text("Intet forbrug de seneste 30 dage endnu.").foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Graf over forbruget de seneste 30 dage")
    }

    private func axisDecimals(_ points: [CloudUsageLog.DayPoint]) -> Int {
        let largest = points.map(\.kroner).max() ?? 0
        return largest >= 1 ? 2 : largest >= 0.1 ? 3 : 4
    }

    private func value(_ point: CloudUsageLog.DayPoint) -> Double {
        measure == .price ? point.kroner : Double(point.entry.checks)
    }

    private func tooltip(for day: Date, points: [CloudUsageLog.DayPoint]) -> some View {
        let today = points.filter { Calendar(identifier: .gregorian).isDate($0.day, inSameDayAs: day) }
        return VStack(alignment: .leading, spacing: 4) {
            Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "da_DK"))))
                .font(.caption.weight(.semibold))
            ForEach(today) { point in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(Self.color(point.feature)).frame(width: 8, height: 8)
                    Text(point.feature.title)
                    Spacer(minLength: 12)
                    Text(point.entry.checks == 1 ? "1 gang" : "\(point.entry.checks) gange").foregroundStyle(.secondary)
                    Text(UsageView.kroner(point.kroner, decimals: 4)).monospacedDigit()
                }
                .font(.caption)
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.1)))
        .frame(minWidth: 220)
    }
}

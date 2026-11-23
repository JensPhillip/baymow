import Foundation
import Combine

// Forbrug af internet-hjælpen (AP-65). Kun tal gemmes – aldrig tekst: antal kontroller og tokens pr. firma og måned.

/// Priser pr. million tokens (standard, ikke batch). Et skøn: den præcise regning står hos firmaerne.
/// Tjekket 23. november 2026: Anthropics egne priser og OpenAIs side developers.openai.com/api/docs/pricing.
enum CloudPricing {
    static let checked = "23. november 2026"
    /// Fast kurs. Kurserne i november 2026 lå omkring 6,3–6,6 kr. pr. dollar.
    static let kronerPerDollar = 6.45

    static func dollarsPerMillion(_ provider: CloudProvider) -> (input: Double, output: Double) {
        switch provider {
        case .claude: return (2.00, 10.00) // Claude Sonnet 5.5
        case .openai: return (0.10, 0.50) // GPT-6 Luna
        }
    }

    static func kroner(_ provider: CloudProvider, input: Int, output: Int) -> Double {
        let price = dollarsPerMillion(provider)
        return (Double(input) * price.input + Double(output) * price.output) / 1_000_000 * kronerPerDollar
    }
}

/// Det, Baymow bruger AI til. Forbruget tælles pr. funktion, så det kan ses samlet på siden "AI og nøgler".
enum AIFeature: String, CaseIterable, Identifiable, Sendable, Codable {
    case spelling
    case mail

    var id: String { rawValue }
    var title: String { self == .spelling ? "Stavning" : "Mail" }
    var symbol: String { self == .spelling ? "textformat.abc.dottedunderline" : "envelope.fill" }
}

/// Forbruget for ét firma og én funktion i én måned eller dag.
struct CloudUsageEntry: Codable, Equatable {
    var checks = 0
    var inputTokens = 0
    var outputTokens = 0

    static func + (a: CloudUsageEntry, b: CloudUsageEntry) -> CloudUsageEntry {
        CloudUsageEntry(checks: a.checks + b.checks, inputTokens: a.inputTokens + b.inputTokens,
                        outputTokens: a.outputTokens + b.outputTokens)
    }
}

/// Lægger forbruget sammen pr. måned ("2026-11") og dag, pr. funktion og firma ("mail.openai"). Gemmes i Baymows
/// indstillinger – kun tal, aldrig tekst. Forbrug gemt før AP-72 (kun "openai"/"claude") regnes som stavning.
@MainActor
final class CloudUsageLog: ObservableObject {
    @Published private(set) var months: [String: [String: CloudUsageEntry]] = [:]
    /// Det samme pr. dag ("2026-11-23"), til grafen over tid.
    @Published private(set) var days: [String: [String: CloudUsageEntry]] = [:]
    private let defaults: UserDefaults
    private let now: () -> Date
    private static let key = "spellingCloudUsage"
    private static let dayStorageKey = "spellingCloudUsageDays"

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        months = Self.load(defaults, Self.key)
        days = Self.load(defaults, Self.dayStorageKey)
    }

    private static func load(_ defaults: UserDefaults, _ key: String) -> [String: [String: CloudUsageEntry]] {
        guard let data = defaults.data(forKey: key),
              let saved = try? JSONDecoder().decode([String: [String: CloudUsageEntry]].self, from: data) else { return [:] }
        return saved.mapValues { entries in
            Dictionary(entries.map { ($0.key.contains(".") ? $0.key : "spelling.\($0.key)", $0.value) }, uniquingKeysWith: +)
        }
    }

    private static func slot(_ feature: AIFeature, _ provider: CloudProvider) -> String { "\(feature.rawValue).\(provider.rawValue)" }

    /// Tokens fra ét svar.
    func addTokens(_ provider: CloudProvider, feature: AIFeature = .spelling, input: Int, output: Int) {
        update(provider, feature) { $0.inputTokens += input; $0.outputTokens += output }
    }

    /// Én kontrol eller ét mail-svar (et tryk på genvejen eller "Prøv").
    func addCheck(_ provider: CloudProvider, feature: AIFeature = .spelling) {
        update(provider, feature) { $0.checks += 1 }
    }

    /// Forbruget i en måned, samlet for et firma og/eller en funktion (`nil` = alle).
    func entry(_ provider: CloudProvider? = nil, feature: AIFeature? = nil, month: String? = nil) -> CloudUsageEntry {
        Self.sum(months[month ?? currentMonth] ?? [:], provider: provider, feature: feature).entry
    }

    func kroner(_ provider: CloudProvider? = nil, feature: AIFeature? = nil, month: String? = nil) -> Double {
        Self.sum(months[month ?? currentMonth] ?? [:], provider: provider, feature: feature).kroner
    }

    /// Hvilke firmaer der er brugt til en funktion i en måned.
    func providers(for feature: AIFeature, month: String? = nil) -> [CloudProvider] {
        CloudProvider.allCases.filter { entry($0, feature: feature, month: month).checks > 0 }
    }

    private static func sum(_ slots: [String: CloudUsageEntry], provider: CloudProvider?, feature: AIFeature?)
        -> (entry: CloudUsageEntry, kroner: Double) {
        var total = CloudUsageEntry(), kroner = 0.0
        for p in CloudProvider.allCases where provider == nil || provider == p {
            for f in AIFeature.allCases where feature == nil || feature == f {
                guard let e = slots[slot(f, p)] else { continue }
                total = total + e
                kroner += CloudPricing.kroner(p, input: e.inputTokens, output: e.outputTokens)
            }
        }
        return (total, kroner)
    }

    var currentMonth: String { Self.monthKey(now()) }

    /// Tidligere måneder med forbrug, nyeste først.
    var earlierMonths: [String] { months.keys.filter { $0 != currentMonth }.sorted(by: >) }

    func reset() {
        months = [:]
        days = [:]
        defaults.removeObject(forKey: Self.key)
        defaults.removeObject(forKey: Self.dayStorageKey)
    }

    /// Én søjle i grafen: én dag og én funktion (alle firmaer lagt sammen, hver til sin pris).
    struct DayPoint: Identifiable, Equatable {
        let day: Date
        let feature: AIFeature
        let entry: CloudUsageEntry
        let kroner: Double
        var id: String { "\(CloudUsageLog.dayKey(day))-\(feature.rawValue)" }
    }

    /// De seneste `count` dage, også dage uden forbrug (så grafen viser tiden rigtigt).
    func lastDays(_ count: Int) -> [DayPoint] {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: now())
        return (0..<count).reversed().flatMap { back -> [DayPoint] in
            let day = calendar.date(byAdding: .day, value: -back, to: today) ?? today
            let slots = days[Self.dayKey(day)] ?? [:]
            return AIFeature.allCases.map { feature in
                let total = Self.sum(slots, provider: nil, feature: feature)
                return DayPoint(day: day, feature: feature, entry: total.entry, kroner: total.kroner)
            }
        }
    }

    nonisolated static func dayKey(_ date: Date) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    nonisolated static func monthKey(_ date: Date) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    /// "november 2026"
    nonisolated static func monthName(_ key: String) -> String {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2, (1...12).contains(parts[1]) else { return key }
        let names = ["januar", "februar", "marts", "april", "maj", "juni", "juli", "august", "september", "oktober",
                     "november", "december"]
        return "\(names[parts[1] - 1]) \(parts[0])"
    }

    private func update(_ provider: CloudProvider, _ feature: AIFeature, _ change: (inout CloudUsageEntry) -> Void) {
        let slot = Self.slot(feature, provider)
        let month = currentMonth
        var entry = months[month]?[slot] ?? CloudUsageEntry()
        change(&entry)
        months[month, default: [:]][slot] = entry
        if let data = try? JSONEncoder().encode(months) { defaults.set(data, forKey: Self.key) }

        let day = Self.dayKey(now())
        var dayEntry = days[day]?[slot] ?? CloudUsageEntry()
        change(&dayEntry)
        days[day, default: [:]][slot] = dayEntry
        if let data = try? JSONEncoder().encode(days) { defaults.set(data, forKey: Self.dayStorageKey) }
    }
}

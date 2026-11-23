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

/// Forbruget for ét firma i én måned.
struct CloudUsageEntry: Codable, Equatable {
    var checks = 0
    var inputTokens = 0
    var outputTokens = 0
}

/// Lægger forbruget sammen pr. måned ("2026-11") og firma. Gemmes i Baymows indstillinger.
@MainActor
final class CloudUsageLog: ObservableObject {
    @Published private(set) var months: [String: [String: CloudUsageEntry]] = [:]
    private let defaults: UserDefaults
    private let now: () -> Date
    private static let key = "spellingCloudUsage"

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        if let data = defaults.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([String: [String: CloudUsageEntry]].self, from: data) {
            months = saved
        }
    }

    /// Tokens fra ét svar.
    func addTokens(_ provider: CloudProvider, input: Int, output: Int) {
        update(provider) { $0.inputTokens += input; $0.outputTokens += output }
    }

    /// Én kontrol (et tryk på ⌃⌥R eller "Prøv").
    func addCheck(_ provider: CloudProvider) {
        update(provider) { $0.checks += 1 }
    }

    func entry(_ provider: CloudProvider, month: String? = nil) -> CloudUsageEntry {
        months[month ?? currentMonth]?[provider.rawValue] ?? CloudUsageEntry()
    }

    func kroner(_ provider: CloudProvider, month: String? = nil) -> Double {
        let e = entry(provider, month: month)
        return CloudPricing.kroner(provider, input: e.inputTokens, output: e.outputTokens)
    }

    var currentMonth: String { Self.monthKey(now()) }

    /// Tidligere måneder med forbrug, nyeste først.
    var earlierMonths: [String] { months.keys.filter { $0 != currentMonth }.sorted(by: >) }

    func reset() {
        months = [:]
        defaults.removeObject(forKey: Self.key)
    }

    static func monthKey(_ date: Date) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    /// "november 2026"
    static func monthName(_ key: String) -> String {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2, (1...12).contains(parts[1]) else { return key }
        let names = ["januar", "februar", "marts", "april", "maj", "juni", "juli", "august", "september", "oktober",
                     "november", "december"]
        return "\(names[parts[1] - 1]) \(parts[0])"
    }

    private func update(_ provider: CloudProvider, _ change: (inout CloudUsageEntry) -> Void) {
        let month = currentMonth
        var entry = months[month]?[provider.rawValue] ?? CloudUsageEntry()
        change(&entry)
        months[month, default: [:]][provider.rawValue] = entry
        if let data = try? JSONEncoder().encode(months) { defaults.set(data, forKey: Self.key) }
    }
}

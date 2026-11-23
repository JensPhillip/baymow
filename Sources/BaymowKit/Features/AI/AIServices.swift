import Foundation
import Combine
import BaymowCore

/// Det fælles sted for AI (AP-72): brugerens nøgler, "Prøv", og forbruget pr. funktion. Hver funktion vælger selv
/// sit firma (brugerens ønske 23. november 2026), men nøglerne og forbruget administreres ét sted.
@MainActor
final class AIServices: ObservableObject {
    enum TestResult: Equatable { case testing, ok, failed(CloudSpellingError) }

    /// Hvilke firmaer der er gemt en nøgle til. Selve nøglen ligger kun i nøgleringen.
    @Published private(set) var savedKeys: Set<CloudProvider> = []
    @Published var testResults: [CloudProvider: TestResult] = [:]
    /// Forbruget (kun tal).
    let usage: CloudUsageLog

    init(defaults: UserDefaults = .standard) {
        usage = CloudUsageLog(defaults: defaults)
        refreshKeys()
    }

    func refreshKeys() {
        let keys = Set(CloudProvider.allCases.filter { CloudKeyStore.hasKey(for: $0) })
        if keys != savedKeys { savedKeys = keys }
    }

    func saveKey(_ key: String, for provider: CloudProvider) {
        CloudKeyStore.save(key, for: provider)
        refreshKeys()
        testResults[provider] = nil
    }

    func deleteKey(for provider: CloudProvider) {
        CloudKeyStore.delete(provider)
        refreshKeys()
        testResults[provider] = nil
    }

    /// Forbindelsen til et firma for en funktion; `nil`, hvis der ikke er en nøgle. Tokens tælles på funktionen.
    func corrector(_ provider: CloudProvider, feature: AIFeature, level: SpellingLevel = .standard) -> CloudSpellingCorrector? {
        guard let key = CloudKeyStore.key(for: provider) else { return nil }
        let usage = usage
        return CloudSpellingCorrector(provider: provider, key: key, level: level, onUsage: { input, output in
            Task { @MainActor in usage.addTokens(provider, feature: feature, input: input, output: output) }
        })
    }

    /// Brugeren trykker "Prøv": sender en fast testsætning (aldrig brugerens tekst) og viser, om nøglen virker.
    func testConnection(_ provider: CloudProvider) {
        guard let corrector = corrector(provider, feature: .spelling) else { testResults[provider] = .failed(.noKey); return }
        testResults[provider] = .testing
        Task {
            do {
                try await corrector.test()
                testResults[provider] = .ok
            } catch {
                testResults[provider] = .failed(error as? CloudSpellingError ?? .failed)
            }
        }
    }
}

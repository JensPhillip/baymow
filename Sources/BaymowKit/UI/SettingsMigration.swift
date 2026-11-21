import Foundation

/// Flytter indstillingerne med, når appens id skifter (B9). macOS gemmer indstillinger under appens id, så uden
/// dette ville stemmevalg, hastighed, genvej og afspillerens placering forsvinde. Tilgængelighed-tilladelsen kan
/// ikke flyttes af en app; den skal gives igen.
public enum SettingsMigration {
    /// Tidligere id'er, nyeste først.
    public static let previousIDs = ["dk.baymow.app"]

    /// Kopierer indstillingerne fra det nyeste tidligere id, der har nogen – men kun hvis det nuværende id er tomt,
    /// så intet overskrives. Returnerer det id, der blev flyttet fra.
    @discardableResult
    public static func migrateIfNeeded(defaults: UserDefaults = .standard, currentID: String? = Bundle.main.bundleIdentifier,
                                previousIDs: [String] = previousIDs) -> String? {
        guard let currentID, defaults.persistentDomain(forName: currentID)?.isEmpty ?? true else { return nil }
        for old in previousIDs where old != currentID {
            guard let values = defaults.persistentDomain(forName: old), !values.isEmpty else { continue }
            defaults.setPersistentDomain(values, forName: currentID)
            return old
        }
        return nil
    }
}

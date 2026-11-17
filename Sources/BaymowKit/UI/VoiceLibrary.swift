import AppKit
import BaymowCore

/// Logikken bag stemmebiblioteket i hovedvinduet, holdt adskilt fra visningen, så den kan testes.
enum VoiceLibrary {
    enum Kind: Equatable {
        /// En af macOS' egne stemmer.
        case system
        /// En stemme, Baymow selv henter og installerer.
        case downloaded
        /// En stemme, der kører hos en tjeneste på nettet (B6: findes ikke endnu).
        case cloud

        var displayName: String {
            switch self {
            case .system: return "Systemstemme"
            case .downloaded: return "Hentet stemme"
            case .cloud: return "Cloud-stemme"
            }
        }
    }

    struct Row: Identifiable, Equatable {
        let id: String
        let name: String
        let kind: Kind
        /// Fx "Forbedret · fra macOS" eller "67 MB · forsøgsstemme".
        let details: String
        /// Installeret og klar til brug (kan prøves og vælges).
        let installed: Voice?
        /// Kan hentes eller fjernes af Baymow.
        let downloadable: DownloadableVoice?
        let isChosen: Bool
        /// Bestået stemmeporten; ellers vises "Ikke anbefalet".
        let isApproved: Bool
    }

    /// Baymows danske hovedstemme (B7). Skal hentes af brugeren i Systemindstillinger.
    static let mainDanishVoiceID = AppleSpeechEngine.recommendedDanishVoiceID

    /// Vejen i Systemindstillinger til at hente stemmer, med navnene fra macOS 26 på dansk.
    static let voiceSettingsPath = "Systemindstillinger → Tilgængelighed → Læs og tal → Systemstemme → Administrer stemmer… → Dansk"

    /// Skal vejledningen til at hente hovedstemmen vises?
    static func needsMainVoiceGuide(installed: [Voice]) -> Bool {
        !installed.contains { $0.id == mainDanishVoiceID }
    }

    /// Bibliotekets rækker for ét sprog: installerede stemmer først, derefter stemmer, der kan hentes.
    static func rows(for language: Language, installed: [Voice], downloadable: [DownloadableVoice],
                     isDownloaded: (String) -> Bool, chosenID: String?) -> [Row] {
        let catalogByID = Dictionary(uniqueKeysWithValues: downloadable.map { ($0.id, $0) })
        var rows: [Row] = installed.filter { $0.language == language }.map { voice in
            let entry = catalogByID[voice.id]
            let kind: Kind = entry == nil ? .system : .downloaded
            var parts = [voice.quality.displayName]
            if let entry { parts.append("\(entry.sizeMB) MB") } else { parts.append("fra macOS") }
            return Row(id: voice.id, name: voice.name, kind: kind, details: parts.joined(separator: " · "),
                       installed: voice, downloadable: entry, isChosen: voice.id == chosenID,
                       isApproved: voice.isApprovedDefault)
        }
        for entry in downloadable where entry.language == language && !isDownloaded(entry.id)
            && !rows.contains(where: { $0.id == entry.id }) {
            rows.append(Row(id: entry.id, name: entry.name, kind: .downloaded, details: "\(entry.sizeMB) MB · ikke hentet",
                            installed: nil, downloadable: entry, isChosen: false, isApproved: entry.isApprovedDefault))
        }
        return rows
    }

    /// Åbner "Læs og tal" i Systemindstillinger. Der findes ikke et officielt link; det mest sandsynlige prøves
    /// først, og ellers åbnes Tilgængelighed, hvor vejledningen viser resten af vejen.
    @MainActor
    static func openVoiceSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.universalaccess?SpokenContent",
            "x-apple.systempreferences:com.apple.Accessibility-Settings.extension",
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) { return }
        }
    }
}

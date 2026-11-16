import Foundation
import Combine

/// Overblik over installerede stemmer på tværs af TTS-motorer, og valg af stemme til et sprog.
@MainActor
public final class VoiceCatalog: ObservableObject {
    @Published public private(set) var voices: [Voice] = []

    private let engines: [SpeechEngine]
    private let settings: SettingsStore

    public init(engines: [SpeechEngine], settings: SettingsStore) {
        self.engines = engines
        self.settings = settings
        refresh()
    }

    public func refresh() {
        voices = engines.flatMap { $0.installedVoices() }.sorted {
            if $0.language != $1.language { return $0.language.rawValue < $1.language.rawValue }
            if $0.quality != $1.quality { return $0.quality > $1.quality }
            return $0.name < $1.name
        }
    }

    public func voices(for language: Language) -> [Voice] {
        voices.filter { $0.language == language }
    }

    /// Brugerens valgte stemme til sproget, ellers den bedste installerede.
    public func voice(for language: Language) -> Voice? {
        let candidates = voices(for: language)
        if let id = settings.preferredVoiceIDs[language.rawValue], let chosen = candidates.first(where: { $0.id == id }) {
            return chosen
        }
        // Automatisk valg: kun godkendte stemmer, medmindre der slet ikke findes andre.
        let approved = candidates.filter(\.isApprovedDefault)
        return (approved.isEmpty ? candidates : approved).max { a, b in
            if a.quality != b.quality { return a.quality < b.quality }
            return (a.locale == language.preferredLocale ? 1 : 0) < (b.locale == language.preferredLocale ? 1 : 0)
        }
    }

    public func engine(for voice: Voice) -> SpeechEngine? {
        engines.first { $0.engineID == voice.engineID }
    }
}

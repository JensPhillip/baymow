import Foundation
import NaturalLanguage

/// Sprog appen kan læse op. Nye sprog tilføjes her – resten af appen itererer over `allCases`.
public enum Language: String, CaseIterable, Codable, Sendable, Identifiable {
    case danish = "da"
    case english = "en"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .danish: return "Dansk"
        case .english: return "Engelsk"
        }
    }

    var nlLanguage: NLLanguage {
        switch self {
        case .danish: return .danish
        case .english: return .english
        }
    }

    /// Foretrukken regional variant, når flere stemmer har samme kvalitet.
    var preferredLocale: String {
        switch self {
        case .danish: return "da-DK"
        case .english: return "en-US"
        }
    }

    public var sampleText: String {
        switch self {
        case .danish: return "Hej! Sådan lyder jeg, når jeg læser dansk tekst højt."
        case .english: return "Hello! This is how I sound when I read English text aloud."
        }
    }
}

public enum VoiceQuality: Int, Comparable, Sendable {
    case standard = 1, enhanced = 2, premium = 3, neural = 4

    public static func < (a: VoiceQuality, b: VoiceQuality) -> Bool { a.rawValue < b.rawValue }

    public var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .enhanced: return "Forbedret"
        case .premium: return "Premium"
        case .neural: return "Neural"
        }
    }
}

/// En installeret stemme, uafhængigt af hvilken TTS-motor der leverer den.
public struct Voice: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let language: Language
    public let locale: String
    public let quality: VoiceQuality
    public let engineID: String
    /// Må stemmen vælges automatisk? Kun stemmer, der har bestået stemmeporten (docs/PROJEKTPLAN.md
    /// afsnit 7), og systemets egne. Brugeren kan altid selv vælge en ikke-godkendt stemme.
    public let isApprovedDefault: Bool

    public init(id: String, name: String, language: Language, locale: String, quality: VoiceQuality, engineID: String,
                isApprovedDefault: Bool = true) {
        self.id = id
        self.name = name
        self.language = language
        self.locale = locale
        self.quality = quality
        self.engineID = engineID
        self.isApprovedDefault = isApprovedDefault
    }
}

/// Besked til brugeren, når en oplæsning ikke kan starte.
public enum Notice: Equatable, Sendable {
    case noSelection
    case noPermission
    case unsupported
    case noVoice(Language)
    /// Teksten er længere end `ReadingSessionManager.maxTextLength` – oftest en markering ved et uheld.
    case tooLong

    public var message: String {
        switch self {
        case .noSelection:
            return "Ingen tekst markeret. Markér den tekst, du vil have læst op, og prøv igen. Er det et billede eller en indscannet side, kan teksten ikke markeres – så kan Baymow ikke læse den op endnu."
        case .noPermission:
            return "Baymow mangler tilladelse til at læse markeret tekst. Giv adgang under Tilgængelighed i Systemindstillinger."
        case .unsupported:
            return "Baymow fandt ingen markeret tekst. Markér teksten, og prøv igen. Virker det stadig ikke, kan Baymow måske ikke læse tekst i dette program."
        case .noVoice(let language):
            return "Der er ingen stemme installeret til \(language.displayName.lowercased()). Åbn Baymow for at vælge en stemme."
        case .tooLong:
            return "Teksten er meget lang – flere timers oplæsning. Markér et mindre stykke, og prøv igen."
        }
    }
}

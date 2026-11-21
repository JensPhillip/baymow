import AppKit
import Combine

/// Global tastaturgenvej. `modifiers` er `NSEvent.ModifierFlags.rawValue`.
public struct Shortcut: Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt
    public var keyLabel: String

    public init(keyCode: UInt32, modifiers: UInt, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    /// ⌃⌥S
    public static let standard = Shortcut(
        keyCode: 1,
        modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue,
        keyLabel: "S"
    )

    public var displayString: String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s + keyLabel
    }
}

/// Lokalt gemte indstillinger (UserDefaults). Indeholder aldrig oplæst tekst.
@MainActor
public final class SettingsStore: ObservableObject {
    public static let rateRange: ClosedRange<Double> = 0.5...2.0

    private let defaults: UserDefaults

    /// Sprog der bruges, når sproggenkendelsen er usikker. Dansk ved første opstart.
    @Published public var preferredLanguage: Language { didSet { defaults.set(preferredLanguage.rawValue, forKey: "preferredLanguage") } }
    /// `nil` = automatisk sproggenkendelse. Ellers læses alt op på det valgte sprog.
    @Published public var forcedLanguage: Language? { didSet { defaults.set(forcedLanguage?.rawValue, forKey: "forcedLanguage") } }
    /// Hastighed som faktor, 1.0 = normal.
    @Published public var rate: Double { didSet { defaults.set(rate, forKey: "rate") } }
    @Published public var shortcut: Shortcut {
        didSet {
            defaults.set(Int(shortcut.keyCode), forKey: "shortcut.keyCode")
            defaults.set(Int(shortcut.modifiers), forKey: "shortcut.modifiers")
            defaults.set(shortcut.keyLabel, forKey: "shortcut.keyLabel")
        }
    }
    /// Foretrukken stemme-id pr. sprog (nøgle = sprogkode).
    @Published public var preferredVoiceIDs: [String: String] { didSet { defaults.set(preferredVoiceIDs, forKey: "preferredVoiceIDs") } }
    /// Fremtidig funktion (sprogskift undervejs i en tekst). Gemmes, men bruges ikke i MVP'en.
    @Published public var allowLanguageSwitching: Bool { didSet { defaults.set(allowLanguageSwitching, forKey: "allowLanguageSwitching") } }
    public var playerOrigin: CGPoint? {
        didSet {
            if let p = playerOrigin {
                defaults.set([Double(p.x), Double(p.y)], forKey: "playerOrigin")
            } else {
                defaults.removeObject(forKey: "playerOrigin")
            }
        }
    }
    /// Ordfremhævning (I1): vis teksten i et vindue, og fremhæv ordet, der læses. Slået fra som standard.
    @Published public var showReadingWindow: Bool { didSet { defaults.set(showReadingWindow, forKey: "showReadingWindow") } }
    public var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") } }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preferredLanguage = defaults.string(forKey: "preferredLanguage").flatMap(Language.init(rawValue:)) ?? .danish
        forcedLanguage = defaults.string(forKey: "forcedLanguage").flatMap(Language.init(rawValue:))
        let storedRate = defaults.double(forKey: "rate")
        rate = storedRate == 0 ? 1.0 : min(max(storedRate, Self.rateRange.lowerBound), Self.rateRange.upperBound)
        if defaults.object(forKey: "shortcut.keyCode") != nil, let label = defaults.string(forKey: "shortcut.keyLabel") {
            shortcut = Shortcut(
                keyCode: UInt32(defaults.integer(forKey: "shortcut.keyCode")),
                modifiers: UInt(defaults.integer(forKey: "shortcut.modifiers")),
                keyLabel: label
            )
        } else {
            shortcut = .standard
        }
        preferredVoiceIDs = (defaults.dictionary(forKey: "preferredVoiceIDs") as? [String: String]) ?? [:]
        allowLanguageSwitching = defaults.bool(forKey: "allowLanguageSwitching")
        if let xy = defaults.array(forKey: "playerOrigin") as? [Double], xy.count == 2 {
            playerOrigin = CGPoint(x: xy[0], y: xy[1])
        } else {
            playerOrigin = nil
        }
        hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
        showReadingWindow = defaults.bool(forKey: "showReadingWindow")
    }
}

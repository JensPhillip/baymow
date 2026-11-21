import AVFoundation
import BaymowCore

/// macOS' indbyggede talesyntese. Kører lokalt og offline med de stemmer, der er installeret i systemet.
@MainActor
public final class AppleSpeechEngine: NSObject, SpeechEngine {
    public let engineID = "apple"
    /// Apple melder hvert ord, der siges (`willSpeakRangeOfSpeechString`).
    public let reportsWordProgress = true
    /// 0…1. Sættes til 0 ved lydløse målinger.
    public var volume: Float = 1

    private var synthesizer: AVSpeechSynthesizer?
    private var current: (utterance: AVSpeechUtterance, handler: (SpeechEvent) -> Void)?

    public override init() { super.init() }

    public func installedVoices() -> [Voice] {
        AVSpeechSynthesisVoice.speechVoices().compactMap { voice in
            guard !voice.voiceTraits.contains(.isNoveltyVoice),
                  !voice.identifier.contains(".eloquence."),
                  // Ældre MacinTalk-stemmer (Fred, Ralph m.fl.) er for utydelige til oplæsning.
                  !voice.identifier.hasPrefix("com.apple.speech.synthesis.voice."),
                  let language = Language.allCases.first(where: { voice.language.hasPrefix($0.rawValue + "-") }) else {
                return nil
            }
            let quality: VoiceQuality
            switch voice.quality {
            case .premium: quality = .premium
            case .enhanced: quality = .enhanced
            default: quality = .standard
            }
            return Voice(id: voice.identifier, name: voice.name, language: language, locale: voice.language, quality: quality,
                         engineID: engineID, isApprovedDefault: Self.isApprovedDefault(voice.identifier))
        }
    }

    /// Baymows danske hovedstemme (B7, valgt af brugeren 17. november 2026).
    public nonisolated static let recommendedDanishVoiceID = "com.apple.voice.enhanced.da-DK.Sara"

    /// Apple-stemmer, der er målt og ikke bestod stemmeportens krav 1 (docs/PROJEKTPLAN.md afsnit 7).
    /// De vælges aldrig automatisk, men brugeren kan stadig selv vælge dem. Umålte stemmer er godkendt (B4).
    static let failedVoiceGate: Set<String> = [
        "com.apple.voice.enhanced.da-DK.Magnus", // 21/36, 4,1 % tegnfejl (2026-11-17)
    ]

    static func isApprovedDefault(_ identifier: String) -> Bool { !failedVoiceGate.contains(identifier) }

    public func pronunciationOverrides(for language: Language) -> [String: String] {
        language == .danish ? Self.danishOverrides : [:]
    }

    /// Tom med vilje. For Apples danske stemme (Sara) blev otte stavemåder fundet i ordprøven
    /// (azure→asjur, nice→najs, like→lajk, messenger→messendjer, chatgpt→"tjat ge pe te", docs→doks,
    /// touchscreen→tutsjskrin, checkout→check-out), men på hele sætninger gav de ingen målbar
    /// forbedring (17 → 18 af 30, inden for målestøjen). Se docs/afleveringer/AP-24.md.
    static let danishOverrides: [String: String] = [:]

    public func speak(_ text: String, voice: Voice, rate: Double, onEvent: @escaping (SpeechEvent) -> Void) {
        // Afbrydes en igangværende oplæsning, kasseres synthesizeren. En ny instans er den
        // mest pålidelige måde at undgå hængende pause-tilstand og forsinkede callbacks.
        if current != nil { discardSynthesizer() }

        guard let systemVoice = AVSpeechSynthesisVoice(identifier: voice.id) else {
            onEvent(.failed)
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = systemVoice
        utterance.rate = Self.systemRate(for: rate)
        utterance.volume = volume

        let synthesizer = self.synthesizer ?? {
            let s = AVSpeechSynthesizer()
            s.delegate = self
            self.synthesizer = s
            return s
        }()
        current = (utterance, onEvent)
        synthesizer.speak(utterance)
    }

    public func pause() { synthesizer?.pauseSpeaking(at: .immediate) }

    public func resume() { synthesizer?.continueSpeaking() }

    public func stop() { discardSynthesizer() }

    private func discardSynthesizer() {
        current = nil
        synthesizer?.delegate = nil
        synthesizer?.stopSpeaking(at: .immediate)
        synthesizer = nil
    }

    /// Omsætter hastighedsfaktoren til AVSpeechUtterance-skalaen (0…1, hvor 0,5 er normal).
    static func systemRate(for factor: Double) -> Float {
        let normal = Double(AVSpeechUtteranceDefaultSpeechRate)
        let value = factor <= 1 ? normal * (0.5 + 0.5 * factor) : normal + (factor - 1) * 0.2
        return Float(min(max(value, Double(AVSpeechUtteranceMinimumSpeechRate)), Double(AVSpeechUtteranceMaximumSpeechRate)))
    }

    private func deliver(_ event: SpeechEvent, for utterance: AVSpeechUtterance, endsUtterance: Bool = false) {
        guard let current, current.utterance === utterance else { return }
        if endsUtterance { self.current = nil }
        current.handler(event)
    }
}

extension AppleSpeechEngine: AVSpeechSynthesizerDelegate {
    private nonisolated func onMain(_ work: @escaping @MainActor (AppleSpeechEngine) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated { work(self) }
        }
    }

    public nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        onMain { $0.deliver(.started, for: utterance) }
    }

    public nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        let offset = characterRange.location
        onMain { $0.deliver(.progress(utf16Offset: offset), for: utterance) }
    }

    public nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onMain { $0.deliver(.finished, for: utterance, endsUtterance: true) }
    }
}

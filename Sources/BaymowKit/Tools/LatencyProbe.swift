import Foundation
import BaymowCore

/// Lydløs måling af tid fra `speak` til motoren melder, at talen er startet.
/// Køres med `Baymow --measure-latency`.
@MainActor
public enum LatencyProbe {
    public static func run() {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "baymow.latency-probe")!)
        let apple = AppleSpeechEngine()
        apple.volume = 0
        let piper = BackendSpeechEngine(backend: PiperBackend())
        piper.volume = 0
        let catalog = VoiceCatalog(engines: [piper, apple], settings: settings)

        // Den stemme, appen selv ville vælge, plus alle hentede stemmer – også dem, der ikke er godkendt som standard.
        var voices: [Voice] = []
        for language in Language.allCases {
            if let chosen = catalog.voice(for: language) { voices.append(chosen) } else { print("\(language.rawValue): ingen stemme installeret") }
            voices += catalog.voices(for: language).filter { $0.engineID == piper.engineID && !voices.contains($0) }
        }
        for voice in voices {
            guard let engine = catalog.engine(for: voice) else { continue }
            let language = voice.language
            if voice.engineID == piper.engineID {
                piper.prepare(voice)
                RunLoop.main.run(until: Date().addingTimeInterval(1.5)) // lad modellen indlæse, som appen gør ved start
            }
            var samples: [Int] = []
            for _ in 0..<4 {
                var startedAfter: TimeInterval?
                var done = false
                let begin = Date()
                engine.speak(DanishTextNormalizer.normalize(language.sampleText), voice: voice, rate: 2.0) { event in
                    switch event {
                    case .started: startedAfter = Date().timeIntervalSince(begin)
                    case .finished, .failed: done = true
                    case .progress: break
                    }
                }
                let deadline = Date().addingTimeInterval(15)
                while !done, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
                engine.stop()
                if let startedAfter { samples.append(Int(startedAfter * 1000)) }
            }
            let list = samples.map { "\($0) ms" }.joined(separator: ", ")
            print("\(language.rawValue) · \(voice.name) (\(voice.quality.displayName)): første kald, derefter varme kald: \(list)")
        }
    }
}

import Foundation

/// Lydløs måling af tid fra `speak` til motoren melder, at talen er startet.
/// Køres med `Baymow --measure-latency`.
@MainActor
public enum LatencyProbe {
    public static func run() {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "baymow.latency-probe")!)
        let apple = AppleSpeechEngine()
        apple.volume = 0
        let piper = PiperSpeechEngine()
        piper.volume = 0
        let catalog = VoiceCatalog(engines: [piper, apple], settings: settings)

        for language in Language.allCases {
            guard let voice = catalog.voice(for: language), let engine = catalog.engine(for: voice) else {
                print("\(language.rawValue): ingen stemme installeret")
                continue
            }
            piper.prepare(voice)
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

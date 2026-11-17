import Foundation
import CSherpaOnnx
import BaymowCore

/// Udviklerværktøjer, der køres fra kommandolinjen.
@MainActor
public enum DeveloperTools {
    /// `--synthesize <stemmemappe> <tekstfil> <ud-mappe>`: læser én sætning pr. linje, forbereder teksten
    /// og skriver `00.wav`, `01.wav` … med Piper. Bruges til at måle appens egen oplæsning med talegenkendelse.
    public static func synthesize(voiceDirectory: String, textFile: String, outputDirectory: String, raw: Bool = false,
                                  overrides: Bool = true) -> Int32 {
        guard let model = PiperModel(directory: URL(fileURLWithPath: voiceDirectory)),
              let text = try? String(contentsOfFile: textFile, encoding: .utf8) else {
            print("Kunne ikke indlæse stemme eller tekst")
            return 1
        }
        try? FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)
        let lines = text.split(separator: "\n").map(String.init)
        let begin = Date()
        var seconds = 0.0
        for (index, line) in lines.enumerated() {
            // raw: uden tekstforberedelse, til afprøvning af stavemåder.
            let samples = model.synthesize(raw ? line : prepare(line, engineID: "piper", overrides: overrides), speed: 1.0)
            seconds += Double(samples.count) / model.sampleRate
            let path = "\(outputDirectory)/\(String(format: "%02d", index)).wav"
            _ = samples.withUnsafeBufferPointer { SherpaOnnxWriteWave($0.baseAddress, Int32(samples.count), Int32(model.sampleRate), path) }
        }
        let elapsed = Date().timeIntervalSince(begin)
        print(String(format: "%d sætninger, %.1f s lyd lavet på %.2f s (faktor %.3f)", lines.count, seconds, elapsed, elapsed / max(seconds, 0.001)))
        return 0
    }

    /// `--synthesize-text <stemmemappe> <tekstfil> <ud.wav>`: læser hele teksten med Piper, forberedt og
    /// delt i sætninger på samme måde som i appen, og skriver én lydfil. Bruges til lyttepakker.
    public static func synthesizeText(voiceDirectory: String, textFile: String, output: String) -> Int32 {
        guard let model = PiperModel(directory: URL(fileURLWithPath: voiceDirectory)),
              let text = try? String(contentsOfFile: textFile, encoding: .utf8) else {
            print("Kunne ikke indlæse stemme eller tekst")
            return 1
        }
        var samples: [Float] = []
        for chunk in TextChunker.chunks(for: text) {
            for sentence in BackendSpeechEngine.sentences(in: prepare(chunk, engineID: "piper", overrides: true)) {
                samples += model.synthesize(sentence.text, speed: 1.0)
            }
        }
        let ok = samples.withUnsafeBufferPointer { SherpaOnnxWriteWave($0.baseAddress, Int32(samples.count), Int32(model.sampleRate), output) }
        print(String(format: "%.1f s lyd skrevet til %@", Double(samples.count) / model.sampleRate, output))
        return ok == 1 ? 0 : 1
    }

    /// `--install-voice <id>`: henter og installerer en stemme med samme kode som knappen "Hent".
    public static func installVoice(id: String) -> Int32 {
        guard let voice = DownloadableVoice.catalog.first(where: { $0.id == id }) else {
            print("Ukendt stemme. Mulige: \(DownloadableVoice.catalog.map(\.id))")
            return 1
        }
        let downloader = ModelDownloader()
        var done = false
        downloader.onChange = { done = true }
        downloader.download(voice)
        while !done { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
        if let error = downloader.errors[id] {
            print("Fejl: \(error)")
            return 1
        }
        print("Installeret i \(downloader.store.directory(for: id).path)")
        return downloader.isInstalled(voice) ? 0 : 1
    }

    /// `--player-selftest`: kører den rigtige lydafspiller lydløst med en installeret Piper-stemme og
    /// kontrollerer rækkefølgen af events, at pause holder afspilningen stille, og at stop gør tavs.
    public static func playerSelfTest() -> Int32 {
        let backend = PiperBackend()
        guard let voice = backend.installedVoices().first else {
            print("Ingen Piper-stemme installeret (kør --install-voice piper-da-talesyntese)")
            return 1
        }
        let engine = BackendSpeechEngine(backend: backend)
        engine.volume = 0
        let text = "Dette er første sætning i testen. Dette er anden sætning i testen. Dette er tredje sætning i testen."
        var events: [String] = []
        let record: (SpeechEvent) -> Void = { event in
            switch event {
            case .started: events.append("started")
            case .progress: events.append("progress")
            case .finished: events.append("finished")
            case .failed: events.append("failed")
            }
        }
        func spin(_ seconds: TimeInterval, until done: () -> Bool = { false }) {
            let deadline = Date().addingTimeInterval(seconds)
            while !done(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        }
        var failures = 0
        func check(_ name: String, _ ok: Bool) {
            print("  \(ok ? "ok  " : "FEJL") \(name)\(ok ? "" : " – events: \(events)")")
            if !ok { failures += 1 }
        }

        engine.speak(text, voice: voice, rate: 2.0, onEvent: record)
        spin(20) { events.last == "finished" || events.last == "failed" }
        check("hel oplæsning: started, progress, progress, finished", events == ["started", "progress", "progress", "finished"])

        events = []
        engine.speak(text, voice: voice, rate: 2.0, onEvent: record)
        spin(5) { events.contains("started") }
        engine.pause()
        let duringPause = events.count
        spin(3)
        check("pause: ingen events i 3 sekunder", events.count == duringPause)
        engine.resume()
        spin(20) { events.last == "finished" || events.last == "failed" }
        check("fortsæt: læser til ende", events.last == "finished")

        events = []
        engine.speak(text, voice: voice, rate: 2.0, onEvent: record)
        spin(5) { events.contains("started") }
        engine.stop()
        let afterStop = events.count
        spin(3)
        check("stop: ingen events bagefter", events.count == afterStop && !events.contains("finished"))

        events = []
        engine.speak(text, voice: voice, rate: 2.0, onEvent: record)
        spin(5) { events.contains("started") }
        var second: [String] = []
        engine.speak("Ny tekst erstatter den gamle.", voice: voice, rate: 2.0) { event in
            if case .finished = event { second.append("finished") } else if case .started = event { second.append("started") }
        }
        let oldCount = events.count
        spin(20) { second.last == "finished" }
        check("ny oplæsning erstatter den gamle uden flere events fra den gamle", events.count == oldCount && second == ["started", "finished"])

        print(failures == 0 ? "Afspilleren bestod" : "Afspilleren fejlede i \(failures) punkt(er)")
        return failures == 0 ? 0 : 1
    }

    /// `--normalize`: læser linjer fra standard input og skriver den forberedte tekst (uden udtalelister).
    public static func normalizeStandardInput() {
        while let line = readLine() { print(DanishTextNormalizer.normalize(line)) }
    }

    /// `--prepare <piper|apple>`: som `--normalize`, men med motorens udtaleliste – præcis den tekst,
    /// motoren får i appen.
    public static func prepareStandardInput(engineID: String) {
        while let line = readLine() { print(prepare(line, engineID: engineID, overrides: true)) }
    }

    /// Dansk tekst, som sessionen ville give den til motoren.
    static func prepare(_ text: String, engineID: String, overrides: Bool) -> String {
        let prepared = DanishTextNormalizer.normalize(text)
        guard overrides else { return prepared }
        let list = engineID == "piper" ? PiperBackend.danishOverrides : AppleSpeechEngine.danishOverrides
        return PronunciationOverrides.apply(list, to: prepared)
    }
}

import Foundation
import CSherpaOnnx

/// Udviklerværktøjer, der køres fra kommandolinjen.
@MainActor
public enum DeveloperTools {
    /// `--synthesize <stemmemappe> <tekstfil> <ud-mappe>`: læser én sætning pr. linje, forbereder teksten
    /// og skriver `00.wav`, `01.wav` … med Piper. Bruges til at måle appens egen oplæsning med talegenkendelse.
    public static func synthesize(voiceDirectory: String, textFile: String, outputDirectory: String) -> Int32 {
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
            let samples = model.synthesize(DanishTextNormalizer.normalize(line), speed: 1.0)
            seconds += Double(samples.count) / model.sampleRate
            let path = "\(outputDirectory)/\(String(format: "%02d", index)).wav"
            _ = samples.withUnsafeBufferPointer { SherpaOnnxWriteWave($0.baseAddress, Int32(samples.count), Int32(model.sampleRate), path) }
        }
        let elapsed = Date().timeIntervalSince(begin)
        print(String(format: "%d sætninger, %.1f s lyd lavet på %.2f s (faktor %.3f)", lines.count, seconds, elapsed, elapsed / max(seconds, 0.001)))
        return 0
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

    /// `--normalize`: læser linjer fra standard input og skriver den forberedte tekst.
    public static func normalizeStandardInput() {
        while let line = readLine() { print(DanishTextNormalizer.normalize(line)) }
    }
}

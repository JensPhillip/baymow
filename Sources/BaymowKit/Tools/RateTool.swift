import AVFoundation
import BaymowCore

/// Måleværktøjer til hastighed (I3).
///
/// `--rate-sweep`: hvor lang tid Sara (forbedret) bruger på samme tekst ved forskellige værdier på Apples skala (0–1).
/// `--rate-wavs <faktor> <tekstfil> <ud-mappe>`: én lydfil pr. linje ved Baymows hastighedsfaktor (til stemmetesten).
/// `--rate-stretch <faktor> <ind-mappe> <ud-mappe>`: speeder færdige lydfiler op som `PCMPlayer` gør (uden at ændre tonehøjden).
@MainActor
public enum RateTool {
    static let paragraph = "Mange oplever, at en tekst bliver lettere at forstå, når den bliver læst højt. Derfor bruger flere skoler oplæsning i undervisningen, og mange voksne lytter til artikler og breve i stedet for at læse dem."

    static func voice() -> AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice(identifier: AppleSpeechEngine.recommendedDanishVoiceID) ?? AVSpeechSynthesisVoice(language: "da-DK")
    }

    /// Lyden for én tekst ved en værdi på Apples skala; returnerer sekunder og skriver evt. en wav-fil.
    static func render(_ text: String, appleRate: Float, to file: URL? = nil) -> Double {
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice()
        utterance.rate = appleRate
        var frames: AVAudioFramePosition = 0
        var rate: Double = 22050
        var output: AVAudioFile?
        var done = false
        synthesizer.write(utterance) { buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer else { return }
            if pcm.frameLength == 0 { output = nil; done = true; return } // nil lukker filen, så den er hel.
            rate = pcm.format.sampleRate
            frames += AVAudioFramePosition(pcm.frameLength)
            if let file, output == nil {
                output = try? AVAudioFile(forWriting: file, settings: pcm.format.settings,
                                          commonFormat: pcm.format.commonFormat, interleaved: pcm.format.isInterleaved)
            }
            try? output?.write(from: pcm)
        }
        let end = Date().addingTimeInterval(60)
        while !done, Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        return Double(frames) / rate
    }

    public static func sweep() -> Int32 {
        let base = render(paragraph, appleRate: AVSpeechUtteranceDefaultSpeechRate)
        print(String(format: "Apples standard (%.2f): %.1f s", AVSpeechUtteranceDefaultSpeechRate, base))
        for value in stride(from: Float(0.3), through: 1.0, by: 0.05) {
            let seconds = render(paragraph, appleRate: value)
            print(String(format: "Apple %.2f: %5.1f s  → %.2f× normal tempo", value, seconds, base / seconds))
        }
        for factor in [1.0, 1.5, 2.0, 2.5, 3.0] {
            let seconds = render(paragraph, appleRate: AppleSpeechEngine.systemRate(for: factor))
            print(String(format: "Baymow %.1f× (Apple %.2f): %.1f s → reelt %.2f×", factor,
                         AppleSpeechEngine.systemRate(for: factor), seconds, base / seconds))
        }
        return 0
    }

    public static func wavs(factor: Double, textFile: String, outputDirectory: String) -> Int32 {
        guard let text = try? String(contentsOfFile: textFile, encoding: .utf8) else { return 1 }
        try? FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)
        for (index, line) in text.split(separator: "\n").enumerated() {
            let url = URL(fileURLWithPath: outputDirectory).appendingPathComponent(String(format: "%02d.wav", index))
            _ = render(DanishTextNormalizer.normalize(String(line)), appleRate: AppleSpeechEngine.systemRate(for: factor), to: url)
        }
        return 0
    }

    public static func stretch(factor: Double, inputDirectory: String, outputDirectory: String) -> Int32 {
        try? FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: inputDirectory)) ?? []).filter { $0.hasSuffix(".wav") }
        for name in names.sorted() {
            guard let input = try? AVAudioFile(forReading: URL(fileURLWithPath: inputDirectory).appendingPathComponent(name)) else { return 1 }
            let format = input.processingFormat
            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            let timePitch = AVAudioUnitTimePitch()
            timePitch.rate = Float(factor)
            engine.attach(player)
            engine.attach(timePitch)
            engine.connect(player, to: timePitch, format: format)
            engine.connect(timePitch, to: engine.mainMixerNode, format: format)
            do {
                try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
                try engine.start()
            } catch { return 1 }
            player.scheduleFile(input, at: nil)
            player.play()
            guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096),
                  let output = try? AVAudioFile(forWriting: URL(fileURLWithPath: outputDirectory).appendingPathComponent(name),
                                                settings: format.settings) else { return 1 }
            let total = AVAudioFramePosition(Double(input.length) / factor) + 2048
            while engine.manualRenderingSampleTime < total {
                let frames = min(AVAudioFrameCount(total - engine.manualRenderingSampleTime), buffer.frameCapacity)
                guard (try? engine.renderOffline(frames, to: buffer)) == .success else { break }
                try? output.write(from: buffer)
            }
            engine.stop()
        }
        return 0
    }
}

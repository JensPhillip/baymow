import AVFoundation

/// Fælles lydafspiller for alle backends: en kø af lydbidder med pause, stop og lydstyrke.
@MainActor
public final class PCMPlayer: PCMOutput {
    public var volume: Float = 1 { didSet { player.volume = volume } }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    /// Formatet, afspilleren er koblet til. Bidder med en anden samplerate omregnes hertil.
    private var format: AVAudioFormat?
    /// Tæller op ved hvert stop, så callbacks fra bidder, der blev fjernet, kan kendes og ignoreres.
    private var generation = 0
    private var pendingBuffers = 0

    public init() {
        engine.attach(player)
    }

    public func enqueue(_ chunk: PCMChunk, onPlayed: @escaping () -> Void) -> Bool {
        guard !chunk.samples.isEmpty, let buffer = makeBuffer(for: chunk), start() else { return false }
        let generation = self.generation
        pendingBuffers += 1
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.generation == generation else { return }
                    self.pendingBuffers -= 1
                    onPlayed()
                }
            }
        }
        return true
    }

    public func play() {
        if start() { player.play() }
    }

    public func pause() { player.pause() }

    public func stop() {
        generation += 1
        pendingBuffers = 0
        player.stop()
    }

    // MARK: - Internt

    private func makeBuffer(for chunk: PCMChunk) -> AVAudioPCMBuffer? {
        guard let source = AVAudioFormat(standardFormatWithSampleRate: chunk.sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(chunk.samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(chunk.samples.count)
        chunk.samples.withUnsafeBufferPointer { samples in
            channel.update(from: samples.baseAddress!, count: chunk.samples.count)
        }

        // Koblingen kan kun skiftes, når køen er tom. Ellers omregnes bidden til det aktuelle format.
        if format == nil || (format?.sampleRate != chunk.sampleRate && pendingBuffers == 0) {
            engine.stop()
            engine.connect(player, to: engine.mainMixerNode, format: source)
            player.volume = volume
            format = source
            return buffer
        }
        guard let format, format.sampleRate != chunk.sampleRate else { return buffer }
        return convert(buffer, to: format)
    }

    private func convert(_ buffer: AVAudioPCMBuffer, to target: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: buffer.format, to: target) else { return nil }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .endOfStream
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        return (status == .error || error != nil) ? nil : output
    }

    private func start() -> Bool {
        guard format != nil else { return false }
        if engine.isRunning { return true }
        do {
            try engine.start()
            return true
        } catch {
            return false
        }
    }
}

import XCTest
@testable import BaymowKit

/// Backend til tests: laver ingen lyd, men kan holdes tilbage, fejle og tælle kald.
private final class FakeBackend: SynthesisBackend, @unchecked Sendable {
    let backendID = "fake-backend"
    let requiresNetwork = false

    private let lock = NSLock()
    private var _calls: [String] = []
    /// Når sat, venter hver syntese på et signal, så testen styrer rækkefølgen.
    var gate: DispatchSemaphore?
    /// Sætninger (0-baseret), der skal fejle eller give tom lyd.
    var failingIndex: Int?
    var emptyIndex: Int?
    var sampleRates: [Double] = [22050]

    var calls: [String] {
        lock.lock(); defer { lock.unlock() }
        return _calls
    }

    func installedVoices() -> [Voice] { [] }

    func synthesize(_ sentence: String, voice: Voice, rate: Double) throws -> PCMChunk {
        lock.lock()
        let index = _calls.count
        _calls.append(sentence)
        lock.unlock()
        gate?.wait()
        if index == failingIndex { throw NSError(domain: "fake", code: 1) }
        let rate = sampleRates[min(index, sampleRates.count - 1)]
        return PCMChunk(samples: index == emptyIndex ? [] : [0.1, 0.2, 0.3], sampleRate: rate)
    }
}

/// Afspiller til tests: husker bidderne og lader testen bestemme, hvornår en bid er "afspillet".
/// I modsætning til den rigtige afspiller beholder den callbacks efter stop, så testen kan vise,
/// at motoren selv ignorerer forsinkede callbacks.
@MainActor
private final class FakeOutput: PCMOutput {
    var volume: Float = 1
    var chunks: [PCMChunk] = []
    var callbacks: [() -> Void] = []
    var playCount = 0
    var pauseCount = 0
    var stopCount = 0
    var accepts = true

    func enqueue(_ chunk: PCMChunk, onPlayed: @escaping () -> Void) -> Bool {
        guard accepts else { return false }
        chunks.append(chunk)
        callbacks.append(onPlayed)
        return true
    }
    func play() { playCount += 1 }
    func pause() { pauseCount += 1 }
    func stop() { stopCount += 1 }

    /// Melder bid nummer `index` som afspillet.
    func finishPlaying(_ index: Int) { callbacks[index]() }
}

@MainActor
final class BackendSpeechEngineTests: XCTestCase {
    private let text = "Første sætning er her. Anden sætning er her. Tredje sætning er her."
    private let voice = Voice(id: "v", name: "Test", language: .danish, locale: "da-DK", quality: .neural, engineID: "fake-backend")

    private var backend: FakeBackend!
    private var output: FakeOutput!
    private var engine: BackendSpeechEngine!
    private var events: [String] = []

    override func setUp() async throws {
        backend = FakeBackend()
        output = FakeOutput()
        engine = BackendSpeechEngine(backend: backend, output: output)
        events = []
    }

    private func record(_ event: SpeechEvent) {
        switch event {
        case .started: events.append("started")
        case .progress(let offset): events.append("progress:\(offset)")
        case .finished: events.append("finished")
        case .failed: events.append("failed")
        }
    }

    /// Venter, til betingelsen er sand (syntesen kører på en baggrundskø).
    private func waitUntil(_ description: String, _ condition: () -> Bool) async {
        for _ in 0..<400 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Tidsfrist overskredet: \(description)")
    }

    /// Giver baggrundskøen og hovedkøen tid til at aflevere alt, der måtte være på vej.
    private func settle() async {
        try? await Task.sleep(nanoseconds: 80_000_000)
    }

    private func offset(of word: String) -> Int { (text as NSString).range(of: word).location }

    // MARK: Normalt forløb

    func testSpeaksSentencesInOrderAndReportsProgress() async {
        engine.speak(text, voice: voice, rate: 1.0) { self.record($0) }
        await waitUntil("tre bidder i kø") { output.chunks.count == 3 }

        XCTAssertEqual(backend.calls.count, 3)
        XCTAssertEqual(events, ["started"])
        XCTAssertEqual(output.playCount, 1)

        output.finishPlaying(0)
        output.finishPlaying(1)
        XCTAssertEqual(events, ["started", "progress:\(offset(of: "Anden"))", "progress:\(offset(of: "Tredje"))"])

        output.finishPlaying(2)
        XCTAssertEqual(events.last, "finished")
        XCTAssertEqual(events.filter { $0 == "finished" }.count, 1)
    }

    func testEmptyTextFinishesImmediately() {
        engine.speak("   ", voice: voice, rate: 1.0) { self.record($0) }
        XCTAssertEqual(events, ["finished"])
        XCTAssertTrue(backend.calls.isEmpty)
    }

    func testSentenceWithoutAudioIsSkipped() async {
        backend.emptyIndex = 2
        engine.speak(text, voice: voice, rate: 1.0) { self.record($0) }
        await waitUntil("to bidder i kø og syntesen færdig") { output.chunks.count == 2 && backend.calls.count == 3 }
        await settle()
        output.finishPlaying(0)
        output.finishPlaying(1)
        XCTAssertEqual(events.last, "finished")
    }

    func testChunksKeepTheirSampleRate() async {
        backend.sampleRates = [22050, 24000, 24000]
        engine.speak(text, voice: voice, rate: 1.0) { self.record($0) }
        await waitUntil("tre bidder i kø") { output.chunks.count == 3 }
        XCTAssertEqual(output.chunks.map(\.sampleRate), [22050, 24000, 24000])
    }

    // MARK: Ingen events efter stop

    func testStopDuringSynthesisSendsNoEvents() async {
        let gate = DispatchSemaphore(value: 0)
        backend.gate = gate
        engine.speak(text, voice: voice, rate: 1.0) { self.record($0) }
        await waitUntil("første syntese i gang") { backend.calls.count == 1 }

        engine.stop()
        for _ in 0..<3 { gate.signal() }
        await settle()

        XCTAssertEqual(events, [])
        XCTAssertTrue(output.chunks.isEmpty, "lyd fra en stoppet oplæsning må ikke nå afspilleren")
        XCTAssertEqual(backend.calls.count, 1, "resten af teksten må ikke syntetiseres efter stop")
    }

    func testNewSpeakDuringPlaybackSilencesTheOldOne() async {
        var oldEvents: [String] = []
        engine.speak(text, voice: voice, rate: 1.0) { event in
            if case .started = event { oldEvents.append("started") } else { oldEvents.append("andet") }
        }
        await waitUntil("første oplæsning i kø") { output.chunks.count == 3 }

        engine.speak("Ny tekst er her.", voice: voice, rate: 1.0) { self.record($0) }
        await waitUntil("ny oplæsning i kø") { output.chunks.count == 4 }

        // Forsinkede callbacks fra den gamle oplæsning må ikke give events – hverken til den gamle eller den nye.
        output.finishPlaying(0)
        output.finishPlaying(1)
        output.finishPlaying(2)
        XCTAssertEqual(oldEvents, ["started"])
        XCTAssertEqual(events, ["started"])

        output.finishPlaying(3)
        XCTAssertEqual(events, ["started", "finished"])
    }

    func testPauseThenStopSendsNoEvents() async {
        engine.speak(text, voice: voice, rate: 1.0) { self.record($0) }
        await waitUntil("tre bidder i kø") { output.chunks.count == 3 }
        engine.pause()
        engine.stop()
        output.finishPlaying(0)
        output.finishPlaying(2)
        await settle()

        XCTAssertEqual(events, ["started"])
        XCTAssertEqual(output.pauseCount, 1)
        XCTAssertGreaterThanOrEqual(output.stopCount, 2) // ét fra speak, ét fra stop
    }

    // MARK: Pause

    func testPauseBeforeFirstAudioDoesNotStartPlayback() async {
        let gate = DispatchSemaphore(value: 0)
        backend.gate = gate
        engine.speak(text, voice: voice, rate: 1.0) { self.record($0) }
        await waitUntil("første syntese i gang") { backend.calls.count == 1 }

        engine.pause()
        for _ in 0..<3 { gate.signal() }
        await waitUntil("tre bidder i kø") { output.chunks.count == 3 }
        XCTAssertEqual(output.playCount, 0, "afspilning må ikke starte, mens oplæsningen er på pause")

        engine.resume()
        XCTAssertEqual(output.playCount, 1)
    }

    func testResumeWithoutSpeakDoesNothing() {
        engine.resume()
        engine.pause()
        XCTAssertEqual(output.playCount, 0)
        XCTAssertEqual(output.pauseCount, 0)
    }

    // MARK: Fejl

    func testBackendErrorGivesFailedOnceAndStops() async {
        backend.failingIndex = 1
        engine.speak(text, voice: voice, rate: 1.0) { self.record($0) }
        await waitUntil("fejl meldt") { events.contains("failed") }
        await settle()

        XCTAssertEqual(events, ["started", "failed"])
        XCTAssertEqual(backend.calls.count, 2, "syntesen skal stoppe ved første fejl")

        // Intet mere efter fejlen, heller ikke hvis en bid når at blive meldt afspillet.
        output.finishPlaying(0)
        XCTAssertEqual(events, ["started", "failed"])
    }

    func testFailureOnFirstSentenceGivesFailedWithoutStarted() async {
        backend.failingIndex = 0
        engine.speak(text, voice: voice, rate: 1.0) { self.record($0) }
        await waitUntil("fejl meldt") { !events.isEmpty }
        XCTAssertEqual(events, ["failed"])
    }

    func testOutputThatRejectsAudioGivesFailed() async {
        output.accepts = false
        engine.speak(text, voice: voice, rate: 1.0) { self.record($0) }
        await waitUntil("fejl meldt") { !events.isEmpty }
        XCTAssertEqual(events, ["failed"])
    }

    func testEngineCanSpeakAgainAfterFailure() async {
        backend.failingIndex = 0
        engine.speak(text, voice: voice, rate: 1.0) { self.record($0) }
        await waitUntil("fejl meldt") { events == ["failed"] }

        backend.failingIndex = nil
        events = []
        engine.speak("Ny tekst er her.", voice: voice, rate: 1.0) { self.record($0) }
        await waitUntil("startet igen") { events == ["started"] }
    }
}

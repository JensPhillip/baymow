import Foundation

public enum SpeechEvent: Sendable {
    /// Motoren er begyndt at tale.
    case started
    /// UTF-16-position i den tekst, der blev givet til `speak`, for det ord der læses nu.
    case progress(utf16Offset: Int)
    case finished
    case failed
}

/// Fælles grænseflade til lokale TTS-motorer.
///
/// Kontrakt: Efter `stop()` eller et nyt kald til `speak` må motoren ikke længere sende
/// events fra det forrige `speak`-kald. Det er det, der garanterer oplæsning uden overlap.
@MainActor
public protocol SpeechEngine: AnyObject {
    var engineID: String { get }
    func installedVoices() -> [Voice]
    /// - Parameter rate: hastighedsfaktor, 1.0 = normal.
    func speak(_ text: String, voice: Voice, rate: Double, onEvent: @escaping (SpeechEvent) -> Void)
    func pause()
    func resume()
    func stop()
}

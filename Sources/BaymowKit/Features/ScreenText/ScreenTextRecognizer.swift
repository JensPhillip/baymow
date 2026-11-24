import AppKit
import ScreenCaptureKit
import Vision
import BaymowCore

// Tekst fra skærmen (AP-75, idé I4). Brugeren trækker en firkant; Baymow tager et billede af netop det område og lader
// Macens egen tekstgenkendelse (Vision) læse teksten. Alt sker på Macen: intet netværk, intet gemt på disken.

enum ScreenTextError: Error, Equatable {
    /// Brugeren har ikke givet Baymow lov til at se skærmen (Skærmoptagelse).
    case noPermission
    /// Kræver macOS 15.2 (billede af et område på skærmen).
    case unsupported
    /// Billedet kunne ikke tages.
    case captureFailed
}

/// Én linje fra tekstgenkendelsen, med sin placering (Vision: 0–1, origo nederst til venstre).
struct RecognizedLine: Equatable {
    let text: String
    let box: CGRect
}

enum ScreenTextRecognizer {
    /// Teksten i billedet. Dansk først, så engelsk. Kører ikke på hovedtråden.
    static func recognize(_ image: CGImage) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["da-DK", "en-US"]
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            let lines = (request.results ?? []).compactMap { observation -> RecognizedLine? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return RecognizedLine(text: candidate.string, box: observation.boundingBox)
            }
            return layout(lines)
        }.value
    }

    /// Linjerne sat sammen til tekst, der kan læses op: oppefra og ned (og fra venstre mod højre på samme linje).
    /// Linjer i samme afsnit lægges sammen med mellemrum; et ord, der er delt med bindestreg over to linjer, samles; et
    /// stort mellemrum (mere end en halv linjehøjde) giver et nyt afsnit.
    static func layout(_ lines: [RecognizedLine]) -> String {
        let sorted = lines.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }.sorted { a, b in
            // Samme linje, hvis de overlapper lodret med mere end halvdelen af højden.
            if abs(a.box.midY - b.box.midY) < min(a.box.height, b.box.height) / 2 { return a.box.minX < b.box.minX }
            return a.box.midY > b.box.midY
        }
        var text = ""
        var previous: RecognizedLine?
        for line in sorted {
            let content = line.text.trimmingCharacters(in: .whitespaces)
            if let previous {
                let sameRow = abs(previous.box.midY - line.box.midY) < min(previous.box.height, line.box.height) / 2
                let gap = previous.box.minY - line.box.maxY
                if sameRow {
                    text += "  " + content
                } else if gap > max(previous.box.height, line.box.height) * 0.5 {
                    text += "\n\n" + content
                } else if text.hasSuffix("-"), let first = content.first, first.isLowercase {
                    text.removeLast() // ord delt over to linjer: "lands-\nbyen" → "landsbyen"
                    text += content
                } else {
                    text += " " + content
                }
            } else {
                text = content
            }
            previous = line
        }
        return text
    }
}

/// Tekstgenkendelsen forveksler af og til de danske bogstaver med andre ("højt" → "hejt", "Århus" → "Arhus"; målt
/// på "indscannede" billeder 24. november 2026). Et ord, Macens danske stavekontrol ikke kender, rettes kun, hvis der
/// er præcis ét bud, der alene adskiller sig i æ/ø/å.
@MainActor
enum DanishLetterFix {
    /// Bogstaver, tekstgenkendelsen forveksler: det genkendte → det rigtige.
    static let confusions: [Character: Set<Character>] = [
        "e": ["ø", "æ"], "o": ["ø"], "a": ["å", "æ"], "E": ["Æ", "Ø"], "O": ["Ø"], "A": ["Å", "Æ"],
    ]

    static func apply(_ text: String) -> String { apply(text, checker: SystemWordChecker()) }

    static func apply(_ text: String, checker: WordChecker) -> String {
        let tokens = Tokens(text)
        var out = tokens.separators[0]
        for (i, word) in tokens.words.enumerated() {
            out += fix(word, checker: checker) + tokens.separators[i + 1]
        }
        return out
    }

    static func fix(_ word: String, checker: WordChecker) -> String {
        guard word.count > 1, word.rangeOfCharacter(from: .decimalDigits) == nil,
              checker.isMisspelled(word, language: .danish) else { return word }
        let candidates = checker.guesses(for: word, language: .danish).filter { guess in
            guard guess.count == word.count, guess != word else { return false }
            return zip(word, guess).allSatisfy { written, right in written == right || confusions[written]?.contains(right) == true }
        }
        return candidates.count == 1 ? candidates[0] : word
    }
}

enum ScreenCapture {
    /// Har brugeren givet lov til skærmoptagelse? Spørger ikke.
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Spørger macOS om lov (viser systemets dialog første gang) og åbner Systemindstillinger.
    /// Nyere macOS viser kun dialogen én gang og sætter ikke altid Baymow på listen. Et forsøg på at se skærmens
    /// vinduer (uden at tage billeder) får macOS til at skrive Baymow på listen, så kontakten kan slås til.
    static func requestPermission() {
        if CGRequestScreenCaptureAccess() { return }
        Task {
            _ = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            await MainActor.run {
                if !hasPermission, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    /// Et billede af et område på skærmen. `rect` er i AppKits koordinater (origo nederst til venstre på hovedskærmen).
    static func image(of rect: CGRect) async throws -> CGImage {
        guard hasPermission else { throw ScreenTextError.noPermission }
        guard #available(macOS 15.2, *) else { throw ScreenTextError.unsupported }
        // ScreenCaptureKit bruger skærmkoordinater med origo øverst til venstre.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let flipped = CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
        return try await withCheckedThrowingContinuation { continuation in
            SCScreenshotManager.captureImage(in: flipped) { image, error in
                if let image { continuation.resume(returning: image) } else {
                    continuation.resume(throwing: error.map { _ in ScreenTextError.captureFailed } ?? ScreenTextError.captureFailed)
                }
            }
        }
    }
}

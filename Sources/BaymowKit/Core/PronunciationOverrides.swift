import Foundation

/// Udskifter ord, en stemme udtaler forkert, med en stavemåde, den udtaler rigtigt
/// ("Chrome" → "krovm"). Bruges til engelske ord i dansk tekst.
///
/// Hvilke ord der skal skiftes ud, afhænger af stemmemotoren, så hver motor leverer sin egen liste
/// gennem `SpeechEngine.pronunciationOverrides(for:)`. Listerne er fundet ved måling
/// (tools/stemmetest/word_probe.py), ikke ved gæt.
public enum PronunciationOverrides {
    /// Almindelige danske og engelske endelser, så "Chromes", "clouden" og "updates" også rammes.
    private static let suffixes = "(erne|ernes|ens|ets|ede|en|et|er|es|'s|s|e)?"
    private static var cache: [[String: String]: NSRegularExpression] = [:]
    private static let lock = NSLock()

    /// - Parameter overrides: ord (små bogstaver) → stavemåde, der skal siges i stedet.
    public static func apply(_ overrides: [String: String], to text: String) -> String {
        guard !overrides.isEmpty, let regex = regex(for: overrides) else { return text }
        let ns = text as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let word = ns.substring(with: match.range(at: 1)).lowercased()
            guard let replacement = overrides[word] else { continue }
            let suffixRange = match.range(at: 2)
            let suffix = suffixRange.location == NSNotFound ? "" : ns.substring(with: suffixRange).replacingOccurrences(of: "'", with: "")
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            result += replacement + suffix
            last = match.range.location + match.range.length
        }
        return result + ns.substring(from: last)
    }

    private static func regex(for overrides: [String: String]) -> NSRegularExpression? {
        lock.lock(); defer { lock.unlock() }
        if let cached = cache[overrides] { return cached }
        // Længste ord først, så "smartphone" vinder over et kortere ord, der begynder ens.
        let words = overrides.keys.sorted { $0.count > $1.count }.map(NSRegularExpression.escapedPattern(for:))
        let pattern = #"(?<![\p{L}\p{N}])("# + words.joined(separator: "|") + ")" + suffixes + #"(?![\p{L}\p{N}])"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        cache[overrides] = regex
        return regex
    }
}

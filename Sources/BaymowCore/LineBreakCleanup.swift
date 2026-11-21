import Foundation

/// Rydder op i linjeskift fra PDF'er og andre opsatte tekster (AP-31), før teksten deles i sætninger.
///
/// Tekst fra en PDF har et linjeskift for enden af hver linje – også midt i sætninger – og ord delt med bindestreg
/// over to linjer ("ordblind-" / "hed"). Det giver pauser midt i sætninger og ord, der udtales som to.
/// Gælder alle sprog. Afsnit (tomme linjer), punktopstillinger og korte overskrifter bevares.
public enum LineBreakCleanup {
    /// En linje, der er mindst så lang og ikke slutter med tegnsætning, er brudt midt i en sætning
    /// (en almindelig PDF-linje er 60–90 tegn; overskrifter er kortere).
    static let minimumBrokenLineLength = 40

    public static func clean(_ input: String) -> String {
        // Windows-linjeskift og bløde bindestreger (usynlige orddelingstegn i mange PDF'er).
        var text = input.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        text = text.replacingOccurrences(of: "\u{00AD}\n", with: "").replacingOccurrences(of: "\u{00AD}", with: "")

        var lines = text.components(separatedBy: "\n")
        var index = 0
        while index < lines.count - 1 {
            let line = lines[index]
            let next = lines[index + 1]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let nextTrimmed = next.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !nextTrimmed.isEmpty, !startsListItem(nextTrimmed) else {
                index += 1
                continue
            }
            let nextStartsLower = nextTrimmed.first?.isLowercase == true

            // Ord delt over to linjer: "ordblind-" + "hed" → "ordblindhed".
            if trimmed.hasSuffix("-"), nextStartsLower,
               let beforeHyphen = trimmed.dropLast().last, beforeHyphen.isLetter, beforeHyphen.isLowercase {
                lines[index] = String(trimmed.dropLast()) + nextTrimmed
                lines.remove(at: index + 1)
                continue
            }

            // Sætning brudt over to linjer: saml med et mellemrum.
            let endsSentence = trimmed.last.map { ".!?:;".contains($0) } ?? false
            if !endsSentence && (nextStartsLower || trimmed.count >= minimumBrokenLineLength) {
                lines[index] = trimmed + " " + nextTrimmed
                lines.remove(at: index + 1)
                continue
            }
            index += 1
        }
        return lines.joined(separator: "\n")
    }

    /// Punktopstilling eller nummereret liste: "- ", "• ", "* ", "1. ", "2) ".
    private static func startsListItem(_ line: String) -> Bool {
        if let first = line.first, "-•*–▪◦".contains(first) { return true }
        return line.range(of: #"^\d{1,3}[.)]\s"#, options: .regularExpression) != nil
    }
}

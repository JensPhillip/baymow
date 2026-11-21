import Foundation

/// Kobler ord i den tekst, der siges, til ord i den tekst, brugeren ser (ordfremhævning, I1).
///
/// Den sagte tekst er forberedt: "kl. 14.30" siges "klokken fjorten tredive". Ord, der er ens i begge tekster,
/// kobles direkte (længste fælles delfølge). Ord, der kun findes i den sagte tekst, kobles til de ord i den viste
/// tekst, der står mellem de nærmeste fælles ord – så "klokken", "fjorten" og "tredive" alle fremhæver "kl. 14.30".
public struct WordAlignment: Sendable {
    /// UTF-16-områder for ordene i de to tekster.
    let originalWords: [NSRange]
    let spokenWords: [NSRange]
    /// For hvert sagt ord: de viste ord (første…sidste indeks), det svarer til, eller nil, hvis der ikke er nogen.
    let mapping: [ClosedRange<Int>?]

    public init(original: String, spoken: String) {
        let originalWords = Self.words(in: original)
        let spokenWords = Self.words(in: spoken)
        self.originalWords = originalWords
        self.spokenWords = spokenWords
        let a = originalWords.map { (original as NSString).substring(with: $0).lowercased() }
        let b = spokenWords.map { (spoken as NSString).substring(with: $0).lowercased() }
        mapping = Self.align(original: a, spoken: b)
    }

    /// Det område i den viste tekst, der svarer til det sagte ord ved `spokenOffset` (UTF-16).
    public func originalRange(forSpokenOffset spokenOffset: Int) -> NSRange? {
        guard let index = spokenWords.firstIndex(where: { NSMaxRange($0) > spokenOffset }) else { return nil }
        return originalRange(forSpokenWords: index...index)
    }

    /// Det område i den viste tekst, der svarer til et stykke af den sagte tekst (fx en hel sætning).
    public func originalRange(forSpokenRange range: NSRange) -> NSRange? {
        let indices = spokenWords.indices.filter { NSIntersectionRange(spokenWords[$0], range).length > 0 }
        guard let first = indices.first, let last = indices.last else { return nil }
        return originalRange(forSpokenWords: first...last)
    }

    private func originalRange(forSpokenWords words: ClosedRange<Int>) -> NSRange? {
        let targets = words.compactMap { mapping[$0] }
        guard let low = targets.map(\.lowerBound).min(), let high = targets.map(\.upperBound).max() else { return nil }
        let start = originalWords[low].location
        return NSRange(location: start, length: NSMaxRange(originalWords[high]) - start)
    }

    /// Ord = sammenhængende bogstaver og cifre. "14.30" giver to ord, "kl." ét.
    static func words(in text: String) -> [NSRange] {
        guard let regex = try? NSRegularExpression(pattern: #"[\p{L}\p{N}]+"#) else { return [] }
        return regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)).map(\.range)
    }

    /// Længste fælles delfølge, og derefter kobling af de sagte ord, der ikke findes i den viste tekst.
    static func align(original a: [String], spoken b: [String]) -> [ClosedRange<Int>?] {
        let n = a.count, m = b.count
        guard n > 0, m > 0 else { return Array(repeating: nil, count: m) }
        var table = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var matched: [(original: Int, spoken: Int)] = []
        var i = 0, j = 0
        while i < n && j < m {
            if a[i] == b[j] { matched.append((i, j)); i += 1; j += 1 }
            else if table[i + 1][j] >= table[i][j + 1] { i += 1 }
            else { j += 1 }
        }

        var result: [ClosedRange<Int>?] = Array(repeating: nil, count: m)
        for pair in matched { result[pair.spoken] = pair.original...pair.original }
        // Huller: sagte ord mellem to fælles ord kobles til de viste ord i samme hul.
        let anchors = [(original: -1, spoken: -1)] + matched + [(original: n, spoken: m)]
        for (left, right) in zip(anchors, anchors.dropFirst()) where right.spoken - left.spoken > 1 {
            // Halvåbent område: kan være tomt, når de to fælles ord står lige efter hinanden i den viste tekst.
            // (Et lukket område `a...b` med a > b får appen til at gå ned – det skete i 2026-11-21.)
            let originalGap = (left.original + 1)..<right.original
            let target: ClosedRange<Int>?
            if !originalGap.isEmpty {
                target = originalGap.lowerBound...(originalGap.upperBound - 1)
            } else {
                // Ingen viste ord i hullet (et ekstra ord i den sagte tekst): brug nabo-ordet.
                let neighbour = left.original >= 0 ? left.original : (right.original < n ? right.original : nil)
                target = neighbour.map { $0...$0 }
            }
            for spoken in (left.spoken + 1)..<right.spoken { result[spoken] = target }
        }
        return result
    }
}

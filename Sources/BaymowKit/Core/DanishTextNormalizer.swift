import Foundation

/// Skriver dansk tekst om til den form, den skal siges i: tal, årstal, klokkeslæt, datoer, priser,
/// enheder og forkortelser skrives ud som ord.
///
/// Målinger (docs/TEKNISK-VURDERING.md) viste, at dette betyder mere for korrekt oplæsning end
/// valget af stemme, så det gøres ens for alle TTS-motorer, før teksten når motoren.
public enum DanishTextNormalizer {
    // MARK: Tal

    private static let units = ["nul", "en", "to", "tre", "fire", "fem", "seks", "syv", "otte", "ni", "ti", "elleve",
                                "tolv", "tretten", "fjorten", "femten", "seksten", "sytten", "atten", "nitten"]
    private static let tens = [20: "tyve", 30: "tredive", 40: "fyrre", 50: "halvtreds", 60: "tres", 70: "halvfjerds",
                               80: "firs", 90: "halvfems"]
    private static let smallOrdinals = [1: "første", 2: "anden", 3: "tredje", 4: "fjerde", 5: "femte", 6: "sjette",
                                        7: "syvende", 8: "ottende", 9: "niende", 10: "tiende", 11: "ellevte",
                                        12: "tolvte", 13: "trettende", 14: "fjortende", 15: "femtende",
                                        16: "sekstende", 17: "syttende", 18: "attende", 19: "nittende"]
    private static let tensOrdinals = [20: "tyvende", 30: "tredivte", 40: "fyrretyvende", 50: "halvtredsindstyvende",
                                       60: "tresindstyvende", 70: "halvfjerdsindstyvende", 80: "firsindstyvende",
                                       90: "halvfemsindstyvende"]

    private static func below100(_ n: Int, neuter: Bool = false) -> String {
        if n < 20 { return n == 1 && neuter ? "et" : units[n] }
        let unit = n % 10, ten = n - n % 10
        return unit == 0 ? tens[ten]! : "\(units[unit])og\(tens[ten]!)"
    }

    private static func below1000(_ n: Int, neuter: Bool = false) -> String {
        let hundreds = n / 100, rest = n % 100
        var parts: [String] = []
        if hundreds > 0 { parts.append(hundreds == 1 ? "hundrede" : "\(units[hundreds]) hundrede") }
        if rest > 0 {
            if !parts.isEmpty { parts.append("og") }
            parts.append(below100(rest, neuter: neuter))
        }
        return parts.joined(separator: " ")
    }

    /// 1250 → "tusind to hundrede og halvtreds".
    public static func cardinal(_ value: Int) -> String {
        if value == 0 { return "nul" }
        if value < 0 { return "minus " + cardinal(-value) }
        var n = value
        var parts: [String] = []
        let billions = n / 1_000_000_000; n %= 1_000_000_000
        let millions = n / 1_000_000; n %= 1_000_000
        let thousands = n / 1000, rest = n % 1000
        if billions > 0 { parts.append(billions == 1 ? "en milliard" : "\(cardinal(billions)) milliarder") }
        if millions > 0 { parts.append(millions == 1 ? "en million" : "\(cardinal(millions)) millioner") }
        if thousands > 0 { parts.append(thousands == 1 ? "tusind" : "\(below1000(thousands, neuter: true)) tusind") }
        if rest > 0 {
            if !parts.isEmpty, rest < 100 { parts.append("og") }
            parts.append(below1000(rest))
        }
        return parts.joined(separator: " ")
    }

    /// 21 → "enogtyvende".
    public static func ordinal(_ n: Int) -> String {
        if let small = smallOrdinals[n] { return small }
        if n < 100 {
            let unit = n % 10, ten = n - n % 10
            return unit == 0 ? tensOrdinals[ten]! : "\(units[unit])og\(tensOrdinals[ten]!)"
        }
        return cardinal(n) + "ende"
    }

    /// 1999 → "nitten hundrede og nioghalvfems", 2026 → "to tusind og seksogtyve".
    public static func year(_ n: Int) -> String {
        guard (1100...1999).contains(n) else { return cardinal(n) }
        let century = n / 100, rest = n % 100
        return "\(units[century]) hundrede" + (rest > 0 ? " og \(below100(rest))" : "")
    }

    private static func decimal(whole: Int, fraction: String) -> String {
        let spoken: String
        if fraction.count <= 2, !fraction.hasPrefix("0"), let value = Int(fraction) {
            spoken = below100(value)
        } else {
            spoken = fraction.compactMap { $0.wholeNumberValue }.map { units[$0] }.joined(separator: " ")
        }
        return "\(cardinal(whole)) komma \(spoken)"
    }

    private static func integer(_ digits: String) -> Int {
        Int(digits.replacingOccurrences(of: ".", with: "")) ?? 0
    }

    // MARK: Regler

    private static let months = "januar|februar|marts|april|maj|juni|juli|august|september|oktober|november|december"
    /// Heltal, evt. med punktum som tusindtalsseparator.
    private static let number = #"\d{1,3}(?:\.\d{3})+|\d+"#

    private static let abbreviations: [(String, String)] = [
        (#"\bbl\.\s?a\."#, "blandt andet"), (#"\bf\.\s?eks\."#, "for eksempel"), (#"\bfx\b"#, "for eksempel"),
        (#"\bca\."#, "cirka"), (#"\bdvs\."#, "det vil sige"), (#"\bosv\."#, "og så videre"),
        (#"\bm\.v\."#, "med videre"), (#"\bmv\."#, "med videre"), (#"\bm\.fl\."#, "med flere"),
        (#"\bmfl\."#, "med flere"), (#"\bpga\."#, "på grund af"), (#"\bevt\."#, "eventuelt"),
        (#"\bnr\."#, "nummer"), (#"\btlf\."#, "telefon"), (#"\bmio\."#, "millioner"), (#"\bmia\."#, "milliarder"),
        (#"\bkl\."#, "klokken"), (#"\bkr\."#, "kroner"), (#"\bjf\."#, "jævnfør"), (#"\bhhv\."#, "henholdsvis"),
        (#"\binkl\."#, "inklusive"), (#"\bekskl\."#, "eksklusive"), (#"\bmin\.(?=\s+\d|\s*$)"#, "minutter"),
        (#"\bst\."#, "sankt"), (#"\bdr\."#, "doktor"), (#"\bmht\."#, "med hensyn til"),
        (#"\bift\."#, "i forhold til"), (#"\bo\.lign\."#, "og lignende"), (#"\bvha\."#, "ved hjælp af"),
    ]

    private static let unitsAfterNumber: [(String, String)] = [
        ("%", "procent"), ("km/t", "kilometer i timen"), ("km", "kilometer"), ("kg", "kilo"), ("cm", "centimeter"),
        ("mm", "millimeter"), ("m²|m2", "kvadratmeter"), ("°C", "grader"), ("°", "grader"), ("kr", "kroner"),
        ("g", "gram"), ("m", "meter"), ("l", "liter"), ("t", "timer"),
    ]

    public static func normalize(_ input: String) -> String {
        var text = replace(#"\s+"#, in: input) { _ in " " }.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return text }
        let startedUppercase = text.first.map { $0.isUppercase } ?? false

        text = text.replacingOccurrences(of: "&", with: " og ").replacingOccurrences(of: "§", with: "paragraf ")
        for (pattern, spoken) in abbreviations {
            text = replace(pattern, in: text, caseInsensitive: true) { _ in spoken }
        }

        // Klokkeslæt: "klokken 14.30" og "07:45"
        let clock: ([String]) -> String = { g in
            let hour = Int(g[2]) ?? 0, minute = Int(g[3]) ?? 0
            let minutes = minute == 0 ? "" : " \(minute < 10 ? "nul " : "")\(below100(minute))"
            return g[1] + cardinal(hour) + minutes
        }
        text = replace(#"(klokken )(\d{1,2})[.:](\d{2})\b"#, in: text, transform: clock)
        text = replace(#"()\b([01]?\d|2[0-3]):([0-5]\d)\b"#, in: text, transform: clock)

        // Datoer: "d. 3. maj", "den 21. juni", "den 21."
        text = replace(#"\bd\.\s?(?=\d)"#, in: text) { _ in "den " }
        text = replace(#"\b(\d{1,2})\.\s?("# + months + #")\b"#, in: text, caseInsensitive: true) { g in
            "\(ordinal(Int(g[1]) ?? 0)) \(g[2])"
        }
        text = replace(#"\bden (\d{1,2})\.(?!\d)"#, in: text) { g in "den \(ordinal(Int(g[1]) ?? 0))" }

        // Årstal: fire cifre 1100–2099, når ordet foran tyder på et årstal
        let yearContext = #"(\b(?:i|år|året|fra|siden|til|før|efter|omkring|"# + months + #")\s)"#
        text = replace(yearContext + #"(1[1-9]\d\d|20\d\d)\b(?![.,]\d)"#, in: text, caseInsensitive: true) { g in
            g[1] + year(Int(g[2]) ?? 0)
        }

        // Kroner og øre: "249,95 kr"
        text = replace("(" + number + #"),(\d{2})\s?(?:kroner|kr)\b"#, in: text) { g in
            "\(cardinal(integer(g[1]))) kroner og \(below100(Int(g[2]) ?? 0))"
        }

        // Tal med enhed: "21 km", "68 %"
        for (unit, spoken) in unitsAfterNumber {
            let escaped = unit.split(separator: "|").map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "|")
            text = replace("((?:" + number + #")(?:,\d+)?)\s?(?:"# + escaped + #")(?![\wæøåÆØÅ])"#, in: text) { g in
                "\(g[1]) \(spoken)"
            }
        }

        // Decimaltal, heltal og løse cifre
        text = replace("(" + number + #"),(\d+)"#, in: text) { g in decimal(whole: integer(g[1]), fraction: g[2]) }
        text = replace(#"(?<![\w])(?:"# + number + #")(?![\w])"#, in: text) { g in cardinal(integer(g[0])) }
        text = replace(#"\d"#, in: text) { g in " \(units[Int(g[0]) ?? 0]) " }

        text = replace(#"\s+"#, in: text) { _ in " " }.trimmingCharacters(in: .whitespaces)
        if startedUppercase, let first = text.first, first.isLowercase {
            text = first.uppercased() + text.dropFirst()
        }
        return text
    }

    // MARK: Regex-hjælper

    private static var cache: [String: NSRegularExpression] = [:]
    private static let cacheLock = NSLock()

    private static func regex(_ pattern: String, caseInsensitive: Bool) -> NSRegularExpression? {
        let key = (caseInsensitive ? "i:" : "s:") + pattern
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = cache[key] { return cached }
        let compiled = try? NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
        cache[key] = compiled
        return compiled
    }

    /// Erstatter hvert match med resultatet af `transform`, der får grupperne (gruppe 0 = hele matchet).
    private static func replace(_ pattern: String, in text: String, caseInsensitive: Bool = false,
                                transform: ([String]) -> String) -> String {
        guard let regex = regex(pattern, caseInsensitive: caseInsensitive) else { return text }
        let ns = text as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let groups = (0..<match.numberOfRanges).map { index -> String in
                let range = match.range(at: index)
                return range.location == NSNotFound ? "" : ns.substring(with: range)
            }
            result += transform(groups)
            last = match.range.location + match.range.length
        }
        return result + ns.substring(from: last)
    }
}

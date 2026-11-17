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

    /// "0105" → "nul en nul fem".
    private static func digitByDigit(_ digits: String) -> String {
        digits.compactMap { $0.wholeNumberValue }.map { units[$0] }.joined(separator: " ")
    }

    /// Telefonnummer i par: "28145690" → "otteogtyve fjorten seksoghalvtreds halvfems"; "05" → "nul fem".
    private static func pairs(_ digits: String) -> String {
        var result: [String] = []
        var index = digits.startIndex
        while index < digits.endIndex {
            let end = digits.index(index, offsetBy: 2, limitedBy: digits.endIndex) ?? digits.endIndex
            let pair = String(digits[index..<end])
            result.append(pair.hasPrefix("0") || pair.count == 1 ? digitByDigit(pair) : below100(Int(pair) ?? 0))
            index = end
        }
        return result.joined(separator: " ")
    }

    /// Klokkeslæt uden "klokken": "14", "30" → "fjorten tredive"; minutter "00" udelades.
    private static func clockTime(hour: String, minute: String?) -> String {
        let minuteValue = Int(minute ?? "") ?? 0
        let minutes = minuteValue == 0 ? "" : " \(minuteValue < 10 ? "nul " : "")\(below100(minuteValue))"
        return cardinal(Int(hour) ?? 0) + minutes
    }

    /// Romertal I–L. Returnerer nil for ugyldige talord som "IIII" eller "VX".
    static func romanValue(_ text: String) -> Int? {
        let values: [Character: Int] = ["I": 1, "V": 5, "X": 10, "L": 50]
        var total = 0, previous = 0
        for character in text.reversed() {
            guard let value = values[character] else { return nil }
            total += value < previous ? -value : value
            previous = max(previous, value)
        }
        guard (1...50).contains(total), roman(total) == text else { return nil }
        return total
    }

    private static func roman(_ n: Int) -> String {
        let table: [(Int, String)] = [(50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
        var rest = n, result = ""
        for (value, symbol) in table { while rest >= value { result += symbol; rest -= value } }
        return result
    }

    /// Brøk som ord: (1, 2) → "en halv", (3, 4) → "tre fjerdedele". Nil, hvis det ikke ligner en brøk.
    private static func fraction(_ numerator: Int, _ denominator: Int) -> String? {
        let parts = [3: "tredjedel", 4: "fjerdedel", 5: "femtedel", 6: "sjettedel", 8: "ottendedel", 10: "tiendedel"]
        guard numerator >= 1, numerator < denominator else { return nil }
        if denominator == 2 { return "en halv" }
        guard let part = parts[denominator] else { return nil }
        return numerator == 1 ? "en \(part)" : "\(cardinal(numerator)) \(part)e"
    }

    /// Webadresse eller mail, som den siges: "www.dr.dk" → "w w w punktum d r punktum d k".
    private static func spokenAddress(_ address: String) -> String {
        var text = address.lowercased()
        if let scheme = text.range(of: #"^https?://"#, options: .regularExpression) { text.removeSubrange(scheme) }
        let separators: [Character: String] = [".": "punktum", "/": "skråstreg", "@": "snabel-a", "-": "bindestreg",
                                               "_": "understregning", ":": "kolon"]
        var words: [String] = []
        var part = ""
        func flush() {
            guard !part.isEmpty else { return }
            // Dele uden vokaler kan ikke udtales som ord og staves: "dk" → "d k".
            let vowels = Set("aeiouyæøå")
            let isLetters = part.allSatisfy(\.isLetter)
            words.append(isLetters && !part.contains(where: vowels.contains) ? part.map(String.init).joined(separator: " ") : part)
            part = ""
        }
        for character in text {
            if let spoken = separators[character] {
                flush()
                words.append(spoken)
            } else if character.isLetter || character.isNumber {
                part.append(character)
            } else {
                flush()
            }
        }
        flush()
        if words.last == "skråstreg" { words.removeLast() }
        return words.joined(separator: " ")
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
        (#"\bpct\b\.?"#, "procent"),
    ]

    /// Regenter og paver: "Christian IV" → "Christian den Fjerde".
    private static let regents = "Christian|Frederik|Margrethe|Erik|Valdemar|Knud|Oluf|Christoffer|Kristian|Karl|Gustav|"
        + "Henrik|Ludvig|Louis|Henry|Elizabeth|Elisabeth|Charles|George|Edward|Richard|Wilhelm|Olav|Haakon|Harald|"
        + "Pius|Johannes|Benedikt|Leo|Gregor|Katarina|Catherine|Napoleon"
    /// Ord, hvor et romertal bagefter er et grundtal: "kapitel III" → "kapitel tre".
    private static let numberedParts = "kapitel|del|bind|afsnit|fase|niveau|trin|sæson|akt|bilag|nummer"

    private static let unitsAfterNumber: [(String, String)] = [
        ("%", "procent"), ("km/t", "kilometer i timen"), ("km", "kilometer"), ("kg", "kilo"), ("cm", "centimeter"),
        ("mm", "millimeter"), ("m²|m2", "kvadratmeter"), ("°C", "grader"), ("°", "grader"), ("kr", "kroner"),
        ("g", "gram"), ("m", "meter"), ("l", "liter"), ("t", "timer"),
    ]

    public static func normalize(_ input: String) -> String {
        var text = replace(#"\s+"#, in: input) { _ in " " }.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return text }
        let startedUppercase = text.first.map { $0.isUppercase } ?? false

        // Webadresser og mail først, før forkortelserne ændrer "dr." og lignende inde i adressen.
        text = replace(#"[\w.+-]+@(?:[\w-]+\.)+[a-z]{2,}"#, in: text, caseInsensitive: true) { g in spokenAddress(g[0]) }
        text = replace(#"(?:https?://)?(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+(?:dk|com|org|net|eu|no|se|de|io|nu|info|uk|fr|gov|edu|app|dev)\b(?:/[\w\-./%?=&]*[\w/])?"#,
                       in: text, caseInsensitive: true) { g in spokenAddress(g[0]) }

        // Valuta før forkortelser: "kr. 249,-", "DKK 500", "€40", "$10" → beløbet først, valutaen bagefter.
        let amount = "((?:" + number + #")(?:,\d+)?)"#
        text = replace(#"(?<!\d)(?<!\d )\b(?:kr\.|DKK)\s?"# + amount + #"(?:,-)?"#, in: text) { g in "\(g[1]) kroner" }
        text = replace(#"€\s?"# + amount, in: text) { g in "\(g[1]) euro" }
        text = replace(#"\$\s?"# + amount, in: text) { g in "\(g[1]) dollar" }
        text = replace(#"£\s?"# + amount, in: text) { g in "\(g[1]) pund" }
        text = replace(amount + #"\s?€"#, in: text) { g in "\(g[1]) euro" }
        text = replace("(" + number + "),-", in: text) { g in g[1] }
        for (code, spoken) in [("DKK", "kroner"), ("EUR", "euro"), ("USD", "dollar"), ("GBP", "pund"),
                               ("SEK", "svenske kroner"), ("NOK", "norske kroner")] {
            text = replace(#"\b"# + code + #"\b"#, in: text) { _ in spoken }
        }

        text = text.replacingOccurrences(of: "&", with: " og ")
        text = text.replacingOccurrences(of: "§§", with: "paragrafferne ").replacingOccurrences(of: "§", with: "paragraf ")
        // "stk. 2" (i love) er "stykke to"; "5 stk." er "fem stykker".
        text = replace(#"(\d)\s?stk\."#, in: text, caseInsensitive: true) { g in "\(g[1]) stykker" }
        text = replace(#"\bstk\.\s?(?=\d)"#, in: text, caseInsensitive: true) { _ in "stykke " }
        text = replace(#"\bstk\."#, in: text, caseInsensitive: true) { _ in "stykker" }
        for (pattern, spoken) in abbreviations {
            text = replace(pattern, in: text, caseInsensitive: true) { _ in spoken }
        }

        // Romertal: "Christian IV" → "Christian den Fjerde"; "kapitel III" → "kapitel tre".
        text = replace(#"\b("# + regents + #")\s+([IVXL]{1,6})\b"#, in: text) { g in
            guard let value = romanValue(g[2]) else { return g[0] }
            let spoken = ordinal(value)
            return "\(g[1]) den \(spoken.prefix(1).uppercased() + spoken.dropFirst())"
        }
        text = replace(#"\b((?i:"# + numberedParts + #"))\s+([IVXL]{1,6})\b"#, in: text) { g in
            guard let value = romanValue(g[2]) else { return g[0] }
            return "\(g[1]) \(cardinal(value))"
        }

        // Klokkeslæt: "klokken 9-16", "klokken 10.30-12.00", "klokken 14.30" og "07:45"
        text = replace(#"(klokken )(\d{1,2})(?:[.:](\d{2}))?\s?[-–]\s?(\d{1,2})(?:[.:](\d{2}))?\b"#, in: text) { g in
            g[1] + clockTime(hour: g[2], minute: g[3]) + " til " + clockTime(hour: g[4], minute: g[5])
        }
        text = replace(#"(klokken )(\d{1,2})[.:](\d{2})\b"#, in: text) { g in g[1] + clockTime(hour: g[2], minute: g[3]) }
        text = replace(#"\b([01]?\d|2[0-3]):([0-5]\d)\b"#, in: text) { g in clockTime(hour: g[1], minute: g[2]) }

        // Datoer: "d. 3. maj", "den 21. juni", "den 21.", "den 3/5"
        text = replace(#"\bd\.\s?(?=\d)"#, in: text) { _ in "den " }
        text = replace(#"\b(\d{1,2})\.\s?("# + months + #")\b"#, in: text, caseInsensitive: true) { g in
            "\(ordinal(Int(g[1]) ?? 0)) \(g[2])"
        }
        text = replace(#"\bden (\d{1,2})/(\d{1,2})\b"#, in: text) { g in
            "den \(ordinal(Int(g[1]) ?? 0)) i \(ordinal(Int(g[2]) ?? 0))"
        }
        text = replace(#"\bden (\d{1,2})\.(?!\d)"#, in: text) { g in "den \(ordinal(Int(g[1]) ?? 0))" }
        // ISO-dato: "2024-11-17" → "den syttende november to tusind og fireogtyve".
        let monthNames = months.split(separator: "|").map(String.init)
        text = replace(#"(?<![\d-])(1[1-9]\d\d|20\d\d)-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])(?![\d-])"#, in: text) { g in
            "den \(ordinal(Int(g[3]) ?? 1)) \(monthNames[(Int(g[2]) ?? 1) - 1]) \(year(Int(g[1]) ?? 0))"
        }

        // Numre, der læses ciffer for ciffer eller i par: CPR, lange numre, telefonnumre, grupper med foranstillet nul.
        text = replace(#"(?<![\d.,])(\d{6})-(\d{4})(?!\d)"#, in: text) { g in "\(digitByDigit(g[1])) \(digitByDigit(g[2]))" }
        text = replace(#"(?<![\d.,])\d{9,}(?!\d|[.,]\d)"#, in: text) { g in digitByDigit(g[0]) }
        text = replace(#"(?<![\d.,])\d{8}(?!\d|[.,]\d)"#, in: text) { g in pairs(g[0]) }
        text = replace(#"(?<![\d.,])0\d+(?!\d|[.,]\d)"#, in: text) { g in digitByDigit(g[0]) }

        // Intervaller: "10-15" → "10 til 15". Ikke i datoer som 2024-11-17 (to bindestreger).
        let interval = "((?:" + number + #")(?:,\d+)?)"#
        text = replace(#"(?<![\d.,-])"# + interval + #"\s?[-–]\s?"# + interval + #"(?![\d-])"#, in: text) { g in
            // "3-1" er et resultat ("tre en"), ikke et interval; et interval går opad ("10-15").
            let left = integer(g[1].components(separatedBy: ",")[0]), right = integer(g[2].components(separatedBy: ",")[0])
            return left >= right ? "\(g[1]) \(g[2])" : "\(g[1]) til \(g[2])"
        }

        // Årstal: fire cifre 1100–2099, når ordet foran tyder på et årstal
        let yearContext = #"(\b(?:i|år|året|fra|siden|til|før|efter|omkring|"# + months + #")\s)"#
        text = replace(yearContext + #"(1[1-9]\d\d|20\d\d)\b(?![.,]\d)"#, in: text, caseInsensitive: true) { g in
            g[1] + year(Int(g[2]) ?? 0)
        }
        // Fortegn: "-5" → "minus 5", "+45" → "plus 45".
        text = replace(#"(?<![\w\d])[-−](?=\d)"#, in: text) { _ in "minus " }
        text = replace(#"(?<![\w\d])\+(?=\d)"#, in: text) { _ in "plus " }

        // Brøker: "1½" → "halvanden", "1/2" → "en halv", "3/4" → "tre fjerdedele".
        text = replace(#"(\d+)½"#, in: text) { g in
            let whole = Int(g[1]) ?? 0
            return whole == 1 ? "halvanden" : "\(cardinal(whole)) og en halv"
        }
        text = text.replacingOccurrences(of: "½", with: "en halv")
        text = replace(#"(?<![\d/.,])(\d{1,2})/(\d{1,2})(?![\d/])"#, in: text) { g in
            fraction(Int(g[1]) ?? 0, Int(g[2]) ?? 0) ?? g[0]
        }

        // Kroner og øre: "249,95 kr"; euro og dollar med cent: "12,50 euro"
        text = replace("(" + number + #"),(\d{2})\s?(?:kroner|kr)\b"#, in: text) { g in
            "\(cardinal(integer(g[1]))) kroner og \(below100(Int(g[2]) ?? 0))"
        }
        text = replace("(" + number + #"),(\d{2})\s?(euro|dollar)\b"#, in: text) { g in
            let cents = Int(g[2]) ?? 0
            return "\(cardinal(integer(g[1]))) \(g[3])" + (cents == 0 ? "" : " og \(below100(cents)) cent")
        }

        // Tal med enhed: "21 km", "68 %"
        for (unit, spoken) in unitsAfterNumber {
            let escaped = unit.split(separator: "|").map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "|")
            text = replace("((?:" + number + #")(?:,\d+)?)\s?(?:"# + escaped + #")(?![\wæøåÆØÅ])"#, in: text) { g in
                "\(g[1]) \(spoken)"
            }
        }

        // Årstal 1100–1999 uden tusindtalspunktum, også uden kontekstord: "1864 var" → "atten hundrede og fireogtres".
        text = replace(#"(?<![\d.,])(1[1-9]\d\d)(?!\d|[.,]\d)"#, in: text) { g in year(Int(g[1]) ?? 0) }

        // Ordenstal foran et ord med lille begyndelsesbogstav: "3. plads" → "tredje plads".
        text = replace(#"(?<![\d.,])(\d{1,3})\.\s(?=[a-zæøå])"#, in: text) { g in "\(ordinal(Int(g[1]) ?? 0)) " }

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

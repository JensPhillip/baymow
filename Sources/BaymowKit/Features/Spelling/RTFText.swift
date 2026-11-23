import Foundation

/// Retter direkte i et programs egen RTF (AP-69). Kun de synlige tegn skiftes ud; skrifttyper, størrelser, fed,
/// punktform og alt andet står præcis, som programmet skrev det.
///
/// Målt 23. november 2026: Når RTF fra Word blev læst og skrevet igen af macOS, blev skrifttypen Aptos til Helvetica,
/// og størrelsen blev skrevet i pixel. Derfor ingen omvej her.
enum RTFText {
    /// Ét synligt tegn (én UTF-16-enhed) og hvor det står i RTF-koden.
    struct Visible {
        var text: [UInt16] = []
        var sources: [Range<Int>] = []
    }

    /// Retter `data`. `nil`, hvis RTF'en ikke kan læses, eller rettelserne ikke kan findes – så bruges ren tekst.
    static func apply(_ segments: [SpellingSegment], to data: Data) -> Data? {
        guard let source = String(data: data, encoding: .ascii) ?? String(data: data, encoding: .isoLatin1),
              source.hasPrefix("{\\rtf") else { return nil }
        let bytes = Array(source.utf8)
        let visible = read(bytes)
        let string = String(utf16CodeUnits: visible.text, count: visible.text.count) as NSString
        guard let edits = RichReplacement.edits(segments, in: string) else { return nil }

        var out = bytes
        for edit in edits.reversed() {
            let escaped = Array(escape(edit.text).utf8)
            if edit.range.length == 0 {
                // En tilføjelse (fx et komma) står lige efter tegnet før, med dets formatering.
                let at = edit.range.location > 0 ? visible.sources[edit.range.location - 1].upperBound
                    : (visible.sources.first?.lowerBound ?? out.count)
                out.insert(contentsOf: escaped, at: at)
            } else {
                // De gamle tegn fjernes ét for ét (formateringskoder imellem bliver stående), og det nye står, hvor det
                // første tegn stod.
                let positions = Array(edit.range.location..<(edit.range.location + edit.range.length))
                for index in positions.dropFirst().reversed() { out.removeSubrange(visible.sources[index]) }
                out.replaceSubrange(visible.sources[positions[0]], with: escaped)
            }
        }
        return Data(out)
    }

    /// De synlige tegn i RTF-koden. Grupper som skrifttabeller, farver, billeder og felter med `\*` springes over.
    static func read(_ bytes: [UInt8]) -> Visible {
        var visible = Visible()
        var codePage = 1252
        struct State { var skip = false; var unicodeSkip = 1 }
        var stack: [State] = []
        var state = State()
        var i = 0

        func add(_ units: [UInt16], _ range: Range<Int>) {
            guard !state.skip else { return }
            for unit in units { visible.text.append(unit); visible.sources.append(range) }
        }

        while i < bytes.count {
            let byte = bytes[i]
            switch byte {
            case UInt8(ascii: "{"):
                stack.append(state); i += 1
            case UInt8(ascii: "}"):
                state = stack.popLast() ?? State(); i += 1
            case UInt8(ascii: "\n"), UInt8(ascii: "\r"):
                i += 1
            case UInt8(ascii: "\\"):
                let start = i
                i += 1
                guard i < bytes.count else { break }
                let next = bytes[i]
                if isLetter(next) {
                    var name = ""
                    while i < bytes.count, isLetter(bytes[i]) { name.append(Character(UnicodeScalar(bytes[i]))); i += 1 }
                    var parameter: Int?
                    var digits = ""
                    if i < bytes.count, bytes[i] == UInt8(ascii: "-") { digits = "-"; i += 1 }
                    while i < bytes.count, isDigit(bytes[i]) { digits.append(Character(UnicodeScalar(bytes[i]))); i += 1 }
                    if !digits.isEmpty { parameter = Int(digits) }
                    if i < bytes.count, bytes[i] == UInt8(ascii: " ") { i += 1 }
                    let range = start..<i
                    switch name {
                    case "ansicpg": codePage = parameter ?? 1252
                    case "uc": state.unicodeSkip = parameter ?? 1
                    case "u":
                        if var value = parameter {
                            if value < 0 { value += 65536 }
                            // De ASCII-tegn, der følger som reserve, hører til samme synlige tegn.
                            var end = i
                            var left = state.unicodeSkip
                            while left > 0, end < bytes.count, bytes[end] != UInt8(ascii: "\\"),
                                  bytes[end] != UInt8(ascii: "{"), bytes[end] != UInt8(ascii: "}") {
                                end += 1; left -= 1
                            }
                            if left > 0, end + 3 < bytes.count, bytes[end] == UInt8(ascii: "\\"), bytes[end + 1] == UInt8(ascii: "'") {
                                end += 4
                            }
                            add([UInt16(value)], start..<end)
                            i = end
                        }
                    case "par", "line": add([10], range)
                    case "tab": add([9], range)
                    case "emdash": add([0x2014], range)
                    case "endash": add([0x2013], range)
                    case "bullet": add([0x2022], range)
                    case "lquote": add([0x2018], range)
                    case "rquote": add([0x2019], range)
                    case "ldblquote": add([0x201C], range)
                    case "rdblquote": add([0x201D], range)
                    default:
                        if destinations.contains(name) { state.skip = true }
                    }
                } else {
                    i += 1
                    switch next {
                    case UInt8(ascii: "'"):
                        guard i + 1 < bytes.count, let value = UInt8(String(bytes: bytes[i...(i + 1)], encoding: .ascii) ?? "", radix: 16) else { break }
                        i += 2
                        add(decode(value, codePage: codePage), start..<i)
                    case UInt8(ascii: "\\"), UInt8(ascii: "{"), UInt8(ascii: "}"):
                        add([UInt16(next)], start..<i)
                    case UInt8(ascii: "~"): add([0xA0], start..<i)
                    case UInt8(ascii: "_"): add([0x2011], start..<i)
                    case UInt8(ascii: "*"): state.skip = true
                    case UInt8(ascii: "\n"), UInt8(ascii: "\r"): add([10], start..<i)
                    default: break // \- (blød bindestreg) og andre er usynlige
                    }
                }
            default:
                add([UInt16(byte)], i..<(i + 1))
                i += 1
            }
        }
        return visible
    }

    /// Ny tekst skrevet som RTF: specialtegn med \u (i sin egen gruppe, så reserve-tegnet altid springes over).
    static func escape(_ text: String) -> String {
        var out = ""
        for unit in text.utf16 {
            switch unit {
            case 92: out += "\\\\"
            case 123: out += "\\{"
            case 125: out += "\\}"
            case 10: out += "\\line "
            case 9: out += "\\tab "
            case 32...126: out.append(Character(UnicodeScalar(UInt8(unit))))
            default: out += "{\\uc1\\u\(Int(Int16(bitPattern: unit)))?}"
            }
        }
        return out
    }

    private static let destinations: Set<String> = [
        "fonttbl", "colortbl", "stylesheet", "info", "pict", "header", "footer", "headerl", "headerr", "headerf",
        "footerl", "footerr", "footerf", "listtable", "listoverridetable", "rsidtbl", "generator", "xmlnstbl",
        "themedata", "colorschememapping", "datastore", "latentstyles", "pgdsctbl", "fldinst", "object", "expandedcolortbl",
        "listtext", "pntext", "bkmkstart", "bkmkend", "nonshppict", "shppict", "filetbl", "revtbl", "mmathPr",
    ]

    private static func isLetter(_ b: UInt8) -> Bool { (b >= 65 && b <= 90) || (b >= 97 && b <= 122) }
    private static func isDigit(_ b: UInt8) -> Bool { b >= 48 && b <= 57 }

    private static func decode(_ value: UInt8, codePage: Int) -> [UInt16] {
        let encoding: String.Encoding = codePage == 10000 ? .macOSRoman : .windowsCP1252
        return Array((String(data: Data([value]), encoding: encoding) ?? "?").utf16)
    }
}

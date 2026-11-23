import AppKit

// Formateringen bevares ved "Brug rettelsen" (AP-68): fed, kursiv, punktform og links bliver stående, fordi rettelserne
// sættes ind i en formateret kopi af markeringen i stedet for at erstatte den med ren tekst.

enum RichReplacement {
    /// Én ændring i den synlige tekst: tegnene i `range` skiftes ud med `text` (et tomt område er en tilføjelse).
    struct Edit: Equatable {
        let range: NSRange
        let text: String
    }

    /// Finder rettelserne i den formaterede teksts synlige tegn. `nil`, hvis stykkerne ikke kan findes i den rigtige
    /// rækkefølge – så bruges ren tekst som før.
    ///
    /// Ord findes ved at søge fremad; det, der springes over, må kun være mellemrum, linjeskift eller punkttegn fra
    /// punktform (fx "•" eller "1."). Tegnene mellem ordene skal stå lige efter det forrige ord.
    static func edits(_ segments: [SpellingSegment], in visible: NSString) -> [Edit]? {
        var edits: [Edit] = []
        var cursor = 0
        for segment in segments {
            let isWord = segment.original.rangeOfCharacter(from: .alphanumerics) != nil
            let found: NSRange
            if segment.original.isEmpty {
                found = NSRange(location: cursor, length: 0)
            } else if isWord {
                let range = visible.range(of: segment.original, options: [],
                                          range: NSRange(location: cursor, length: visible.length - cursor))
                guard range.location != NSNotFound,
                      onlyLayout(visible.substring(with: NSRange(location: cursor, length: range.location - cursor))) else { return nil }
                found = range
            } else {
                let here = NSRange(location: cursor, length: min(segment.original.utf16.count, visible.length - cursor))
                guard visible.substring(with: here) == segment.original else {
                    // Tegnene står anderledes i den formaterede tekst (fx et linjeskift som punktform): uændrede
                    // mellemrum springes over; ændrede kan ikke placeres sikkert.
                    if segment.text == segment.original { continue }
                    return nil
                }
                found = here
            }
            if segment.text != segment.original { edits.append(Edit(range: found, text: segment.text)) }
            cursor = found.location + found.length
        }
        return edits
    }

    /// Retter en formateret tekst (bruges til HTML, fx fra Google Docs og Chrome).
    static func apply(_ segments: [SpellingSegment], to rich: NSAttributedString) -> NSAttributedString? {
        guard let edits = edits(segments, in: rich.string as NSString) else { return nil }
        let result = NSMutableAttributedString(attributedString: rich)
        for edit in edits.reversed() {
            // Det nye får formateringen fra det første tegn, det erstatter (eller tegnet før, ved en tilføjelse).
            let at = edit.range.length == 0 ? edit.range.location - 1 : edit.range.location
            let attributes = result.length == 0 ? [:] : result.attributes(at: min(max(at, 0), result.length - 1), effectiveRange: nil)
            result.replaceCharacters(in: edit.range, with: NSAttributedString(string: edit.text, attributes: attributes))
        }
        return result
    }

    /// Kun mellemrum, linjeskift og punkttegn fra punktform.
    private static func onlyLayout(_ skipped: String) -> Bool {
        let layout = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "•◦▪–-*·0123456789.)\t\u{2028}\u{2029}\u{FFFC}"))
        return skipped.unicodeScalars.allSatisfy(layout.contains)
    }

    /// Det, der skal sættes ind: i samme format, som programmet selv lagde på udklipsholderen.
    enum Formatted {
        /// Programmets egen RTF, rettet direkte (Word, Pages, Mail, Noter): skrifttyper og størrelser er urørte.
        case rtf(Data)
        /// HTML (fx Google Docs og Chrome).
        case html(Data)
    }

    /// Retter det formaterede indhold, der ligger på udklipsholderen. RTF foretrækkes og rettes direkte; ellers HTML.
    @MainActor
    static func formatted(from pasteboard: NSPasteboard, segments: [SpellingSegment]) -> Formatted? {
        if let data = pasteboard.data(forType: .rtf) {
            return RTFText.apply(segments, to: data).map(Formatted.rtf)
        }
        if let data = pasteboard.data(forType: .html),
           let text = NSAttributedString(html: data, documentAttributes: nil),
           let fixed = apply(segments, to: text),
           let html = try? fixed.data(from: NSRange(location: 0, length: fixed.length),
                                      documentAttributes: [.documentType: NSAttributedString.DocumentType.html]) {
            return .html(html)
        }
        return nil
    }

    /// Den rettede tekst i det format, programmet gav, plus ren tekst.
    static func pasteboardItem(formatted: Formatted?, plain: String) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        switch formatted {
        case .rtf(let data): item.setData(data, forType: .rtf)
        case .html(let data): item.setData(data, forType: .html)
        case nil: break
        }
        item.setString(plain, forType: .string)
        // Udklipsholder-programmer bedes om ikke at gemme teksten (nspasteboard.org).
        item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        return item
    }
}

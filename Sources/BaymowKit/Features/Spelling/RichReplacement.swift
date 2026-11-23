import AppKit

// Formateringen bevares ved "Brug rettelsen" (AP-68): fed, kursiv, punktform og links bliver stående, fordi rettelserne
// sættes ind i en formateret kopi af markeringen i stedet for at erstatte den med ren tekst.

enum RichReplacement {
    /// Retter den formaterede tekst stykke for stykke. `nil`, hvis stykkerne ikke kan findes i den rigtige rækkefølge –
    /// så bruges ren tekst som før.
    ///
    /// Ord findes ved at søge fremad; det, der springes over, må kun være mellemrum, linjeskift eller punkttegn fra
    /// punktform (fx "•" eller "1."). Tegnene mellem ordene skal stå lige efter det forrige ord.
    static func apply(_ segments: [SpellingSegment], to rich: NSAttributedString) -> NSAttributedString? {
        let result = NSMutableAttributedString(attributedString: rich)
        var cursor = 0
        for segment in segments {
            let text = result.string as NSString
            let isWord = segment.original.rangeOfCharacter(from: .alphanumerics) != nil
            let found: NSRange
            if segment.original.isEmpty {
                found = NSRange(location: cursor, length: 0)
            } else if isWord {
                let range = text.range(of: segment.original, options: [], range: NSRange(location: cursor, length: text.length - cursor))
                guard range.location != NSNotFound,
                      onlyLayout(text.substring(with: NSRange(location: cursor, length: range.location - cursor))) else { return nil }
                found = range
            } else {
                let here = NSRange(location: cursor, length: min(segment.original.utf16.count, text.length - cursor))
                guard text.substring(with: here) == segment.original else {
                    // Tegnene står anderledes i den formaterede tekst (fx et linjeskift som punktform): uændrede
                    // mellemrum springes over; ændrede kan ikke placeres sikkert.
                    if segment.text == segment.original { continue }
                    return nil
                }
                found = here
            }
            if segment.text != segment.original {
                // Det nye får formateringen fra det første tegn, det erstatter (eller tegnet før, ved en tilføjelse).
                let attributes: [NSAttributedString.Key: Any] = result.length == 0 ? [:]
                    : result.attributes(at: min(max(found.location - (found.length == 0 ? 1 : 0), 0), result.length - 1),
                                        effectiveRange: nil)
                result.replaceCharacters(in: found, with: NSAttributedString(string: segment.text, attributes: attributes))
                cursor = found.location + segment.text.utf16.count
            } else {
                cursor = found.location + found.length
            }
        }
        return result
    }

    /// Kun mellemrum, linjeskift og punkttegn fra punktform.
    private static func onlyLayout(_ skipped: String) -> Bool {
        let layout = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "•◦▪–-*·0123456789.)\t\u{2028}\u{2029}\u{FFFC}"))
        return skipped.unicodeScalars.allSatisfy(layout.contains)
    }

    /// Den formaterede udgave af det, der ligger på udklipsholderen (RTF foretrækkes, ellers HTML).
    @MainActor
    static func richText(from pasteboard: NSPasteboard) -> NSAttributedString? {
        if let data = pasteboard.data(forType: .rtf),
           let text = NSAttributedString(rtf: data, documentAttributes: nil) { return text }
        if let data = pasteboard.data(forType: .html),
           let text = NSAttributedString(html: data, documentAttributes: nil) { return text }
        return nil
    }

    /// Skriver den rettede tekst som RTF, HTML og ren tekst, så programmet selv vælger den bedste.
    static func pasteboardItem(rich: NSAttributedString?, plain: String) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        if let rich {
            let range = NSRange(location: 0, length: rich.length)
            if let rtf = try? rich.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
                item.setData(rtf, forType: .rtf)
            }
            if let html = try? rich.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.html]) {
                item.setData(html, forType: .html)
            }
        }
        item.setString(plain, forType: .string)
        // Udklipsholder-programmer bedes om ikke at gemme teksten (nspasteboard.org).
        item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        return item
    }
}

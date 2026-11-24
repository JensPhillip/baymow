import AppKit
import CoreImage
import BaymowCore

/// Måling af tekst fra skærmen (AP-75): `--ocr-test <tekster.txt> <resultat.json>`.
///
/// Egne danske tekster (ét afsnit pr. blok) tegnes som billeder i seks udgaver – skarp, lille uden Retina, med fødder,
/// lysegrå, mørk tilstand og "indscannet" (formindsket, sløret, let skæv) – og læses med Macens tekstgenkendelse.
/// Tallet er tegnfejl (Levenshtein-afstand / antal tegn) og ord-fejl. Ingen brugertekst.
@MainActor
public enum OCRTest {
    struct Style {
        let name: String
        let font: NSFont
        let color: NSColor
        let background: NSColor
        let scale: CGFloat
        let scanned: Bool
    }

    static let styles: [Style] = [
        Style(name: "skarp 15 pt", font: .systemFont(ofSize: 15), color: .black, background: .white, scale: 2, scanned: false),
        Style(name: "lille 11 pt uden Retina", font: .systemFont(ofSize: 11), color: .black, background: .white, scale: 1, scanned: false),
        Style(name: "med fødder 16 pt", font: NSFont(name: "Times New Roman", size: 16) ?? .systemFont(ofSize: 16),
              color: .black, background: .white, scale: 2, scanned: false),
        Style(name: "lysegrå 14 pt", font: .systemFont(ofSize: 14), color: NSColor(white: 0.6, alpha: 1), background: .white,
              scale: 2, scanned: false),
        Style(name: "mørk tilstand 14 pt", font: .systemFont(ofSize: 14), color: NSColor(white: 0.92, alpha: 1),
              background: NSColor(white: 0.12, alpha: 1), scale: 2, scanned: false),
        Style(name: "indscannet 14 pt", font: NSFont(name: "Times New Roman", size: 14) ?? .systemFont(ofSize: 14),
              color: .black, background: NSColor(white: 0.96, alpha: 1), scale: 1, scanned: true),
    ]

    public static func run(textsFile: String, outputFile: String) -> Int32 {
        guard let content = try? String(contentsOfFile: textsFile, encoding: .utf8) else { print("Kan ikke læse \(textsFile)"); return 1 }
        let blocks = content.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        var rows: [[String: Any]] = []
        var summary: [String: Any] = [:]
        for style in styles {
            var charErrors = 0, chars = 0, wordErrors = 0, words = 0
            var seconds = 0.0
            for block in blocks {
                guard let image = render(block, style: style) else { continue }
                let started = Date()
                let found = DanishLetterFix.apply(SpellTest.runBlocking { (try? await ScreenTextRecognizer.recognize(image)) ?? "" })
                seconds += Date().timeIntervalSince(started)
                let reference = normalized(block), result = normalized(found)
                let distance = SpellingGuard.distance(reference, result)
                charErrors += distance
                chars += reference.count
                let referenceWords = reference.split(separator: " ").map(String.init)
                let resultWords = result.split(separator: " ").map(String.init)
                let missing = Set(referenceWords).subtracting(resultWords).count
                wordErrors += missing
                words += Set(referenceWords).count
                rows.append(["udgave": style.name, "facit": reference, "genkendt": result, "tegnfejl": distance])
                if distance > 0 { print("  \(style.name): \(distance) tegnfejl\n    facit:     \(reference)\n    genkendt:  \(result)") }
            }
            let cer = Double(charErrors) / Double(max(chars, 1)) * 100
            let wer = Double(wordErrors) / Double(max(words, 1)) * 100
            summary[style.name] = ["tegnfejl_procent": (cer * 10).rounded() / 10, "ordfejl_procent": (wer * 10).rounded() / 10,
                                   "sekunder_pr_afsnit": (seconds / Double(max(blocks.count, 1)) * 100).rounded() / 100]
            print("\(style.name): \(String(format: "%.1f", cer)) % tegnfejl, \(String(format: "%.1f", wer)) % ord forkert, \(String(format: "%.2f", seconds / Double(max(blocks.count, 1)))) s pr. afsnit")
        }
        let report: [String: Any] = ["dato": ISO8601DateFormatter().string(from: Date()), "afsnit": blocks.count,
                                     "udgaver": summary, "detaljer": rows]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: outputFile))
        }
        return 0
    }

    static func normalized(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Teksten tegnet i en kolonne på 520 punkter, som den kunne stå på skærmen.
    static func render(_ text: String, style: Style) -> CGImage? {
        let width: CGFloat = 520
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        let attributed = NSAttributedString(string: text, attributes: [.font: style.font, .foregroundColor: style.color,
                                                                        .paragraphStyle: paragraph])
        let bounds = attributed.boundingRect(with: NSSize(width: width, height: 10_000), options: [.usesLineFragmentOrigin])
        let size = NSSize(width: width + 40, height: ceil(bounds.height) + 40)
        let pixels = NSSize(width: size.width * style.scale, height: size.height * style.scale)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(pixels.width), pixelsHigh: Int(pixels.height),
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        style.background.setFill()
        NSRect(origin: .zero, size: size).fill()
        attributed.draw(with: NSRect(x: 20, y: 20, width: width, height: bounds.height), options: [.usesLineFragmentOrigin])
        NSGraphicsContext.restoreGraphicsState()
        guard let image = bitmap.cgImage else { return nil }
        return style.scanned ? scan(image) : image
    }

    /// "Indscannet": formindsket, let sløret og 1° skæv.
    static func scan(_ image: CGImage) -> CGImage? {
        let context = CIContext()
        var ci = CIImage(cgImage: image)
        ci = ci.transformed(by: CGAffineTransform(scaleX: 0.8, y: 0.8).rotated(by: .pi / 180))
        ci = ci.applyingGaussianBlur(sigma: 0.6).cropped(to: ci.extent.insetBy(dx: 4, dy: 4))
        return context.createCGImage(ci, from: ci.extent)
    }
}

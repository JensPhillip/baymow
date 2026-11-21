import XCTest
import AppKit
@testable import BaymowCore

/// AP-30: når teksten hentes med kopiering, skal udklipsholderen bagefter være præcis som før – også med billeder
/// og flere elementer. Testen bruger en egen, navngivet udklipsholder; brugerens rigtige røres ikke.
final class ClipboardRestoreTests: XCTestCase {
    private var pasteboard: NSPasteboard!

    override func setUp() {
        pasteboard = NSPasteboard(name: NSPasteboard.Name("dk.baymow.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
    }

    private func pngData() -> Data {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.systemRed.setFill()
        NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        return rep.representation(using: .png, properties: [:])!
    }

    /// Simulerer det, kopieringen gør: et andet program lægger den markerede tekst på udklipsholderen.
    private func simulateCopy() {
        pasteboard.clearContents()
        pasteboard.setString("markeret tekst fra et andet program", forType: .string)
    }

    func testTextIsRestored() {
        pasteboard.setString("brugerens egen tekst", forType: .string)
        let snapshot = TextCaptureService.snapshot(of: pasteboard)
        simulateCopy()
        TextCaptureService.restore(snapshot, to: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), "brugerens egen tekst")
    }

    func testImageAndRichContentAreRestoredByteForByte() {
        let png = pngData()
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        item.setString("billedtekst", forType: .string)
        item.setData(Data("{\\rtf1 fed}".utf8), forType: .rtf)
        pasteboard.writeObjects([item])

        let snapshot = TextCaptureService.snapshot(of: pasteboard)
        simulateCopy()
        TextCaptureService.restore(snapshot, to: pasteboard)

        let restored = pasteboard.pasteboardItems?.first
        XCTAssertEqual(restored?.data(forType: .png), png, "billedet skal være uændret")
        XCTAssertEqual(restored?.string(forType: .string), "billedtekst")
        XCTAssertEqual(restored?.data(forType: .rtf), Data("{\\rtf1 fed}".utf8))
    }

    func testSeveralItemsAreRestoredInOrder() {
        let first = NSPasteboardItem(); first.setString("første", forType: .string)
        let second = NSPasteboardItem(); second.setString("anden", forType: .string)
        pasteboard.writeObjects([first, second])

        let snapshot = TextCaptureService.snapshot(of: pasteboard)
        simulateCopy()
        TextCaptureService.restore(snapshot, to: pasteboard)

        XCTAssertEqual(pasteboard.pasteboardItems?.compactMap { $0.string(forType: .string) }, ["første", "anden"])
    }

    // MARK: Hvad en kopiering gav (fejl fundet af brugeren 2026-11-21)

    func testImageWithItsAddressIsNotReadAloud() {
        let item = NSPasteboardItem()
        item.setData(pngData(), forType: .png)
        item.setString("https://eksempel.dk/billeder/hund.jpg", forType: .string)
        item.setString("<img src=\"https://eksempel.dk/billeder/hund.jpg\">", forType: .html)
        pasteboard.writeObjects([item])
        XCTAssertEqual(TextCaptureService.classifyCopy(on: pasteboard), .notText)
    }

    func testImageWithoutAnyTextIsNotReadAloud() {
        let item = NSPasteboardItem()
        item.setData(pngData(), forType: .png)
        pasteboard.writeObjects([item])
        XCTAssertEqual(TextCaptureService.classifyCopy(on: pasteboard), .notText)
    }

    func testTextAroundAnImageIsStillRead() {
        let item = NSPasteboardItem()
        item.setData(pngData(), forType: .png)
        item.setString("Hunden løb over marken. Bagefter sov den.", forType: .string)
        pasteboard.writeObjects([item])
        XCTAssertEqual(TextCaptureService.classifyCopy(on: pasteboard), .text("Hunden løb over marken. Bagefter sov den."))
    }

    func testASelectedWebAddressIsStillRead() {
        // Markerer brugeren selv en adresse i en tekst, skal den læses op.
        pasteboard.setString("https://www.borger.dk", forType: .string)
        XCTAssertEqual(TextCaptureService.classifyCopy(on: pasteboard), .text("https://www.borger.dk"))
    }

    func testPlainTextIsRead() {
        pasteboard.setString("Almindelig markeret tekst.", forType: .string)
        XCTAssertEqual(TextCaptureService.classifyCopy(on: pasteboard), .text("Almindelig markeret tekst."))
    }

    func testBareAddressRecognition() {
        XCTAssertTrue(TextCaptureService.isBareAddress("https://eksempel.dk/a.jpg"))
        XCTAssertTrue(TextCaptureService.isBareAddress("  data:image/png;base64,AAAA \n"))
        XCTAssertFalse(TextCaptureService.isBareAddress("Se https://eksempel.dk for mere"))
        XCTAssertFalse(TextCaptureService.isBareAddress("Hunden løb"))
    }

    func testEmptyClipboardStaysEmpty() {
        let snapshot = TextCaptureService.snapshot(of: pasteboard)
        simulateCopy()
        TextCaptureService.restore(snapshot, to: pasteboard)
        XCTAssertTrue(pasteboard.pasteboardItems?.isEmpty ?? true,
                      "var udklipsholderen tom før, må den markerede tekst ikke blive liggende")
    }
}

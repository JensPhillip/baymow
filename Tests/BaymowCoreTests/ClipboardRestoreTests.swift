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

    func testEmptyClipboardStaysEmpty() {
        let snapshot = TextCaptureService.snapshot(of: pasteboard)
        simulateCopy()
        TextCaptureService.restore(snapshot, to: pasteboard)
        XCTAssertTrue(pasteboard.pasteboardItems?.isEmpty ?? true,
                      "var udklipsholderen tom før, må den markerede tekst ikke blive liggende")
    }
}

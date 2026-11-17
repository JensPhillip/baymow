import XCTest
@testable import BaymowKit
import BaymowCore

/// AP-40: hvilke stemmer biblioteket viser, og hvornår vejledningen til Sara (forbedret) vises.
final class VoiceLibraryTests: XCTestCase {
    private let compactSara = Voice(id: "com.apple.voice.compact.da-DK.Sara", name: "Sara", language: .danish,
                                    locale: "da-DK", quality: .standard, engineID: "apple")
    private let enhancedSara = Voice(id: "com.apple.voice.enhanced.da-DK.Sara", name: "Sara (forbedret)", language: .danish,
                                     locale: "da-DK", quality: .enhanced, engineID: "apple")
    private let magnus = Voice(id: "com.apple.voice.enhanced.da-DK.Magnus", name: "Magnus (forbedret)", language: .danish,
                               locale: "da-DK", quality: .enhanced, engineID: "apple", isApprovedDefault: false)
    private let samantha = Voice(id: "com.apple.voice.compact.en-US.Samantha", name: "Samantha", language: .english,
                                 locale: "en-US", quality: .standard, engineID: "apple")
    private let piper = DownloadableVoice.catalog[0]

    func testGuideIsShownOnlyWhenSaraEnhancedIsMissing() {
        XCTAssertTrue(VoiceLibrary.needsMainVoiceGuide(installed: [compactSara, samantha]))
        XCTAssertTrue(VoiceLibrary.needsMainVoiceGuide(installed: [compactSara, magnus]))
        XCTAssertFalse(VoiceLibrary.needsMainVoiceGuide(installed: [compactSara, enhancedSara]))
        XCTAssertEqual(VoiceLibrary.mainDanishVoiceID, enhancedSara.id)
    }

    func testRowsShowTypeSizeAndChoice() {
        let rows = VoiceLibrary.rows(for: .danish, installed: [enhancedSara, magnus, compactSara, samantha],
                                     downloadable: [piper], isDownloaded: { _ in false }, chosenID: enhancedSara.id)
        XCTAssertEqual(rows.map(\.id), [enhancedSara.id, magnus.id, compactSara.id, piper.id], "kun danske stemmer, hentbare til sidst")
        XCTAssertEqual(rows[0].kind, .system)
        XCTAssertTrue(rows[0].isChosen)
        XCTAssertEqual(rows[0].details, "Forbedret · fra macOS")
        XCTAssertFalse(rows[1].isApproved, "Magnus bestod ikke stemmeporten")
        XCTAssertEqual(rows[3].kind, .downloaded)
        XCTAssertNil(rows[3].installed, "en stemme, der ikke er hentet, kan ikke prøves eller vælges")
        XCTAssertEqual(rows[3].details, "\(piper.sizeMB) MB · ikke hentet")
    }

    func testDownloadedVoiceAppearsOnceAsInstalled() {
        let installedPiper = Voice(id: piper.id, name: piper.name, language: .danish, locale: "da-DK", quality: .neural,
                                   engineID: "piper", isApprovedDefault: false)
        let rows = VoiceLibrary.rows(for: .danish, installed: [enhancedSara, installedPiper], downloadable: [piper],
                                     isDownloaded: { $0 == self.piper.id }, chosenID: enhancedSara.id)
        let piperRows = rows.filter { $0.id == piper.id }
        XCTAssertEqual(piperRows.count, 1)
        XCTAssertEqual(piperRows[0].kind, .downloaded)
        XCTAssertNotNil(piperRows[0].installed)
        XCTAssertNotNil(piperRows[0].downloadable, "en hentet stemme kan fjernes")
        XCTAssertEqual(piperRows[0].details, "Neural · \(piper.sizeMB) MB")
    }
}

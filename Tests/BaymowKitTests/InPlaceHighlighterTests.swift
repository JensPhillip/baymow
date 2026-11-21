import XCTest
@testable import BaymowKit

/// I1: omregning fra Tilgængelighedens koordinater (0,0 øverst) til vinduernes (0,0 nederst).
@MainActor
final class InPlaceHighlighterTests: XCTestCase {
    func testQuartzRectIsFlippedToAppKit() {
        let quartz = CGRect(x: 100, y: 50, width: 40, height: 20) // 50 punkter fra toppen
        let appKit = InPlaceHighlighter.appKitRect(fromQuartz: quartz, primaryScreenHeight: 1000)
        XCTAssertEqual(appKit, CGRect(x: 100, y: 930, width: 40, height: 20))
    }
}

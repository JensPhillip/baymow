import XCTest
@testable import BaymowKit

/// AP-50: "Om Baymow" nævner licensen og alle indbyggede dele, og stemmer overens med docs/LICENSER.md.
@MainActor
final class AboutBaymowTests: XCTestCase {
    func testCreditsNameLicenseAndEveryComponent() {
        let text = AboutBaymow.creditsText
        XCTAssertTrue(text.contains("GPL-3.0-or-later"))
        for component in AboutBaymow.components {
            XCTAssertTrue(text.contains(component.name), component.name)
        }
    }

    func testComponentsMatchTheLicenceDocument() throws {
        let doc = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("docs/LICENSER.md")
        let text = try String(contentsOf: doc, encoding: .utf8)
        for component in AboutBaymow.components {
            XCTAssertTrue(text.contains(component.name), "\(component.name) mangler i docs/LICENSER.md")
            XCTAssertTrue(text.contains(component.license), "\(component.license) mangler i docs/LICENSER.md")
        }
    }
}

import XCTest
@testable import BaymowKit

/// B9: indstillingerne følger med, når appens id skifter – og intet overskrives.
final class SettingsMigrationTests: XCTestCase {
    private let old = "baymow.tests.old.\(UUID().uuidString)"
    private let new = "baymow.tests.new.\(UUID().uuidString)"
    private let defaults = UserDefaults.standard

    override func tearDown() {
        defaults.removePersistentDomain(forName: old)
        defaults.removePersistentDomain(forName: new)
    }

    func testSettingsAreCopiedFromThePreviousID() {
        defaults.setPersistentDomain(["rate": 1.9, "hasCompletedOnboarding": true, "playerOrigin": [1068.0, 828.0]], forName: old)
        XCTAssertEqual(SettingsMigration.migrateIfNeeded(defaults: defaults, currentID: new, previousIDs: [old]), old)
        let copied = defaults.persistentDomain(forName: new)
        XCTAssertEqual(copied?["rate"] as? Double, 1.9)
        XCTAssertEqual(copied?["hasCompletedOnboarding"] as? Bool, true)
        XCTAssertEqual(copied?["playerOrigin"] as? [Double], [1068, 828])
    }

    func testExistingSettingsAreNeverOverwritten() {
        defaults.setPersistentDomain(["rate": 1.9], forName: old)
        defaults.setPersistentDomain(["rate": 1.2], forName: new)
        XCTAssertNil(SettingsMigration.migrateIfNeeded(defaults: defaults, currentID: new, previousIDs: [old]))
        XCTAssertEqual(defaults.persistentDomain(forName: new)?["rate"] as? Double, 1.2)
    }

    func testNothingHappensWithoutPreviousSettings() {
        XCTAssertNil(SettingsMigration.migrateIfNeeded(defaults: defaults, currentID: new, previousIDs: [old]))
        XCTAssertTrue(defaults.persistentDomain(forName: new)?.isEmpty ?? true)
    }
}

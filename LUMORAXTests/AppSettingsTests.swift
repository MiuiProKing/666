import XCTest
@testable import LUMORAX

@MainActor
final class AppSettingsTests: XCTestCase {
    func testSettingsPersist() {
        let suiteName = "AppSettingsTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated UserDefaults")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let settings = AppSettings(defaults: defaults)
        settings.saveOriginal = true
        settings.gridEnabled = false
        settings.captureQuality = .maximum
        settings.outputFormat = .jpeg

        let restored = AppSettings(defaults: defaults)
        XCTAssertTrue(restored.saveOriginal)
        XCTAssertFalse(restored.gridEnabled)
        XCTAssertEqual(restored.captureQuality, .maximum)
        XCTAssertEqual(restored.outputFormat, .jpeg)
    }
}

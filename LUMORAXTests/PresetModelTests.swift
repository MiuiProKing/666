import XCTest
@testable import LUMORAX

@MainActor
final class PresetModelTests: XCTestCase {
    func testBuiltInPresetIdentifiersAreUnique() {
        let store = PresetStore(defaults: isolatedDefaults())
        let presets = store.presets
        XCTAssertEqual(Set(presets.map(\.id)).count, presets.count)
    }

    func testSignaturePresetIsConservative() {
        let preset = PresetModel.lumoraSignature
        XCTAssertGreaterThan(preset.contrast, 1)
        XCTAssertLessThanOrEqual(preset.sharpening, 0.25)
        XCTAssertLessThan(preset.saturation, 1.05)
        XCTAssertGreaterThan(preset.highlights, 0.5)
    }

    func testPresetRoundTrip() throws {
        let original = PresetModel.lumoraSignature
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PresetModel.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "PresetModelTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return .standard
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

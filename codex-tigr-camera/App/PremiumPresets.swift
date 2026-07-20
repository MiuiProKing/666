import Foundation

enum PremiumPresetID: String, Codable, CaseIterable {
    case off = "без_обработки"
    case fullFramePro = "full_frame_pro"
    case forestSignature = "forest_signature"
    case goldenHourElite = "golden_hour_elite"
    case leicaInspired = "leica_inspired"
    case sonyDetailPro = "sony_detail_pro"
    case canonPortraitPro = "canon_portrait_pro"
    case cinemaNight = "cinema_night"
    case cinematicTealSoft = "cinematic_teal_soft"
    case cleanInstagramPro = "clean_instagram_pro"
}

struct PremiumPresetParameters: Codable {
    var exposure: Float = 0
    var highlights: Float = 0
    var shadows: Float = 0
    var whites: Float = 0
    var blacks: Float = 0
    var contrast: Float = 0
    var vibrance: Float = 0
    var saturation: Float = 0
    var temperatureKelvinOffset: Float = 0
    var tint: Float = 0
    var texture: Float = 0
    var clarity: Float = 0
    var dehaze: Float = 0
    var sharpening: Float = 0
    var noiseReduction: Float = 0
    var vignette: Float = 0
    var grain: Float = 0

    func validated() -> PremiumPresetParameters {
        var p = self
        p.exposure = p.exposure.clamped(-2, 2)
        p.highlights = p.highlights.clamped(-1, 1); p.shadows = p.shadows.clamped(-1, 1)
        p.whites = p.whites.clamped(-1, 1); p.blacks = p.blacks.clamped(-1, 1)
        p.contrast = p.contrast.clamped(-0.5, 0.5); p.vibrance = p.vibrance.clamped(-0.5, 0.5)
        p.saturation = p.saturation.clamped(-0.5, 0.5); p.temperatureKelvinOffset = p.temperatureKelvinOffset.clamped(-1200, 1200)
        p.tint = p.tint.clamped(-0.25, 0.25); p.texture = p.texture.clamped(-0.5, 0.5)
        p.clarity = p.clarity.clamped(-0.5, 0.5); p.dehaze = p.dehaze.clamped(-0.3, 0.3)
        p.sharpening = p.sharpening.clamped(0, 0.5); p.noiseReduction = p.noiseReduction.clamped(0, 1)
        p.vignette = p.vignette.clamped(-0.5, 0); p.grain = p.grain.clamped(0, 0.25)
        return p
    }

    func scaled(_ intensity: Float) -> PremiumPresetParameters {
        let t = intensity.clamped(0, 1)
        var p = self
        p.exposure *= t; p.highlights *= t; p.shadows *= t; p.whites *= t; p.blacks *= t
        p.contrast *= t; p.vibrance *= t; p.saturation *= t; p.temperatureKelvinOffset *= t; p.tint *= t
        p.texture *= t; p.clarity *= t; p.dehaze *= t; p.sharpening *= t; p.noiseReduction *= t
        p.vignette *= t; p.grain *= t
        return p.validated()
    }
}

struct PremiumPreset: Codable, Identifiable {
    var id: String
    var name: String
    var shortName: String
    var version: Int
    var supportedLenses: [String]
    var defaultIntensity: Float
    var parameters: PremiumPresetParameters
    var protectSkin: Bool
    var protectHighlights: Bool
    var reduceSharpeningAtHighISO: Bool
    var ultrawideStrengthMultiplier: Float
    var frontCameraStrengthMultiplier: Float
    var builtIn: Bool

    func validated() -> PremiumPreset {
        var p = self
        p.version = max(1, p.version)
        p.defaultIntensity = p.defaultIntensity.clamped(0, 1)
        p.parameters = p.parameters.validated()
        p.ultrawideStrengthMultiplier = p.ultrawideStrengthMultiplier.clamped(0.45, 1)
        p.frontCameraStrengthMultiplier = p.frontCameraStrengthMultiplier.clamped(0.45, 1)
        if p.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { p.name = "Пользовательский пресет" }
        if p.shortName.isEmpty { p.shortName = "USER" }
        if p.supportedLenses.isEmpty { p.supportedLenses = ["1x", "0.5x", "front"] }
        return p
    }
}

final class PremiumPresetStore {
    static let shared = PremiumPresetStore()
    private let defaults = UserDefaults.standard
    private let selectedKey = "premium.preset.selected.v2"
    private let intensityKey = "premium.preset.intensity.v2"
    private let userKey = "premium.preset.user.v2"

    private(set) var userPresets: [PremiumPreset] = []

    var selectedID: String {
        get { defaults.string(forKey: selectedKey) ?? PremiumPresetID.fullFramePro.rawValue }
        set { defaults.set(newValue, forKey: selectedKey) }
    }

    var intensity: Float {
        get { defaults.object(forKey: intensityKey) == nil ? 1 : defaults.float(forKey: intensityKey).clamped(0, 1) }
        set { defaults.set(newValue.clamped(0, 1), forKey: intensityKey) }
    }

    var all: [PremiumPreset] { Self.builtIns + userPresets }

    private init() {
        if let data = defaults.data(forKey: userKey), let decoded = try? JSONDecoder().decode([PremiumPreset].self, from: data) {
            userPresets = decoded.map { var p = $0.validated(); p.builtIn = false; return p }
        }
        if preset(id: selectedID) == nil { selectedID = PremiumPresetID.fullFramePro.rawValue }
    }

    func preset(id: String) -> PremiumPreset? { all.first { $0.id == id } }

    func select(_ id: String) {
        guard preset(id: id) != nil else { return }
        selectedID = id
    }

    func effective(id: String, intensity: Float, lens: String, iso: Float, faceAware: Bool) -> (PremiumPreset, PremiumPresetParameters)? {
        guard let preset = preset(id: id) else { return nil }
        var strength = intensity.clamped(0, 1)
        if lens == "0.5x" { strength *= preset.ultrawideStrengthMultiplier }
        if lens == "front" { strength *= preset.frontCameraStrengthMultiplier }
        var parameters = preset.parameters.scaled(strength)
        if preset.reduceSharpeningAtHighISO, iso > 500 {
            let reduction = min(0.60, (iso - 500) / 2200)
            parameters.sharpening *= 1 - reduction
            parameters.noiseReduction = max(parameters.noiseReduction, min(0.78, 0.38 + reduction * 0.45))
        }
        if faceAware && preset.protectSkin {
            parameters.clarity = min(parameters.clarity, 0.02)
            parameters.texture = min(parameters.texture, 0.04)
            parameters.saturation = min(parameters.saturation, 0.06)
            parameters.sharpening = min(parameters.sharpening, 0.12)
        }
        return (preset, parameters.validated())
    }

    func duplicate(_ sourceID: String, named name: String) -> PremiumPreset? {
        guard var copy = preset(id: sourceID) else { return nil }
        copy.id = "user_\(UUID().uuidString.lowercased())"
        copy.name = name; copy.shortName = "USER"; copy.builtIn = false
        userPresets.append(copy.validated()); persistUsers(); return copy
    }

    func rename(_ id: String, to name: String) {
        guard let index = userPresets.firstIndex(where: { $0.id == id }) else { return }
        userPresets[index].name = name; userPresets[index] = userPresets[index].validated(); persistUsers()
    }

    func delete(_ id: String) {
        guard userPresets.contains(where: { $0.id == id }) else { return }
        userPresets.removeAll { $0.id == id }
        if selectedID == id { selectedID = PremiumPresetID.fullFramePro.rawValue }
        persistUsers()
    }

    func reorder(from source: Int, to destination: Int) {
        guard userPresets.indices.contains(source), destination >= 0, destination <= userPresets.count else { return }
        let value = userPresets.remove(at: source); userPresets.insert(value, at: min(destination, userPresets.count)); persistUsers()
    }

    func importPreset(data: Data) throws -> PremiumPreset {
        var preset = try JSONDecoder().decode(PremiumPreset.self, from: data).validated()
        preset.id = "user_\(UUID().uuidString.lowercased())"; preset.builtIn = false
        userPresets.append(preset); persistUsers(); return preset
    }

    func exportPreset(id: String) throws -> Data {
        guard let preset = preset(id: id) else { throw CocoaError(.fileNoSuchFile) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(preset)
    }

    private func persistUsers() {
        if let data = try? JSONEncoder().encode(userPresets) { defaults.set(data, forKey: userKey) }
    }

    static let builtIns: [PremiumPreset] = [
        make(.off, "Без обработки", "RAW", .init(), skin: true, highISO: true, ultra: 1, front: 1),
        make(.fullFramePro, "FULL FRAME PRO", "FF", .init(exposure: -0.15, highlights: -0.38, shadows: 0.18, whites: 0.07, blacks: -0.10, contrast: 0.14, vibrance: 0.13, saturation: 0.03, temperatureKelvinOffset: 80, tint: 0.01, texture: 0.10, clarity: 0.06, dehaze: 0, sharpening: 0.16, noiseReduction: 0.40, vignette: -0.06, grain: 0), skin: true, highISO: true, ultra: 0.78, front: 0.72),
        make(.forestSignature, "FOREST SIGNATURE", "FOREST", .init(exposure: -0.25, highlights: -0.46, shadows: 0.12, whites: 0.05, blacks: -0.18, contrast: 0.22, vibrance: 0.16, saturation: 0.05, temperatureKelvinOffset: 180, tint: 0.02, texture: 0.16, clarity: 0.11, dehaze: 0.06, sharpening: 0.18, noiseReduction: 0.35, vignette: -0.14, grain: 0.03), skin: true, highISO: true, ultra: 0.75, front: 0.70),
        make(.goldenHourElite, "GOLDEN HOUR ELITE", "GOLD", .init(highlights: -0.42, shadows: 0.16, whites: 0.08, blacks: -0.13, contrast: 0.18, vibrance: 0.15, saturation: 0.04, temperatureKelvinOffset: 320, tint: 0.03, texture: 0.09, clarity: 0.06, sharpening: 0.15, noiseReduction: 0.30, vignette: -0.08), skin: true, highISO: true, ultra: 0.78, front: 0.75),
        make(.leicaInspired, "LEICA INSPIRED", "LEICA", .init(highlights: -0.34, shadows: 0.10, whites: 0.04, blacks: -0.16, contrast: 0.20, vibrance: 0.08, saturation: -0.03, temperatureKelvinOffset: 70, texture: 0.13, clarity: 0.08, sharpening: 0.17, noiseReduction: 0.32, vignette: -0.10, grain: 0.04), skin: true, highISO: true, ultra: 0.75, front: 0.70),
        make(.sonyDetailPro, "SONY DETAIL PRO", "DETAIL", .init(highlights: -0.32, shadows: 0.20, whites: 0.09, blacks: -0.09, contrast: 0.12, vibrance: 0.12, saturation: 0.02, texture: 0.15, clarity: 0.07, sharpening: 0.20, noiseReduction: 0.28, vignette: -0.04), skin: true, highISO: true, ultra: 0.60, front: 0.65),
        make(.canonPortraitPro, "CANON PORTRAIT PRO", "PORTRAIT", .init(highlights: -0.25, shadows: 0.14, whites: 0.04, blacks: -0.07, contrast: 0.08, vibrance: 0.08, saturation: 0.02, temperatureKelvinOffset: 120, tint: 0.03, texture: -0.04, clarity: -0.05, sharpening: 0.10, noiseReduction: 0.44, vignette: -0.06), skin: true, highISO: true, ultra: 0.72, front: 0.82),
        make(.cinemaNight, "CINEMA NIGHT", "NIGHT", .init(highlights: -0.50, shadows: 0.20, whites: -0.03, blacks: -0.14, contrast: 0.16, vibrance: 0.08, saturation: -0.04, texture: 0.05, clarity: 0.04, sharpening: 0.08, noiseReduction: 0.72, vignette: -0.10, grain: 0.02), skin: true, highISO: true, ultra: 0.62, front: 0.65),
        make(.cinematicTealSoft, "CINEMATIC TEAL SOFT", "TEAL", .init(highlights: -0.38, shadows: 0.14, whites: 0.02, blacks: -0.17, contrast: 0.21, vibrance: 0.07, saturation: -0.05, temperatureKelvinOffset: 50, tint: -0.02, texture: 0.08, clarity: 0.07, sharpening: 0.14, noiseReduction: 0.34, vignette: -0.12, grain: 0.05), skin: true, highISO: true, ultra: 0.72, front: 0.68),
        make(.cleanInstagramPro, "CLEAN INSTAGRAM PRO", "SOCIAL", .init(highlights: -0.30, shadows: 0.22, whites: 0.10, blacks: -0.08, contrast: 0.10, vibrance: 0.16, saturation: 0.04, temperatureKelvinOffset: 60, texture: 0.08, clarity: 0.04, sharpening: 0.14, noiseReduction: 0.30, vignette: -0.03), skin: true, highISO: true, ultra: 0.78, front: 0.76)
    ]

    private static func make(_ id: PremiumPresetID, _ name: String, _ short: String, _ parameters: PremiumPresetParameters, skin: Bool, highISO: Bool, ultra: Float, front: Float) -> PremiumPreset {
        PremiumPreset(id: id.rawValue, name: name, shortName: short, version: 2, supportedLenses: ["1x", "0.5x", "front"], defaultIntensity: 1, parameters: parameters, protectSkin: skin, protectHighlights: true, reduceSharpeningAtHighISO: highISO, ultrawideStrengthMultiplier: ultra, frontCameraStrengthMultiplier: front, builtIn: true)
    }
}

extension Float {
    func clamped(_ lower: Float, _ upper: Float) -> Float { Swift.min(upper, Swift.max(lower, self)) }
}


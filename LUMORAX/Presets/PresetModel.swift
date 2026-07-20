import Foundation

struct PresetModel: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let summary: String
    let exposure: Float
    let contrast: Float
    let highlights: Float
    let shadows: Float
    let temperature: Float
    let tint: Float
    let saturation: Float
    let vibrance: Float
    let sharpening: Float
    let noiseReduction: Float
    let vignette: Float
    let intensity: Float

    static let natural = PresetModel(
        id: "natural",
        name: "NATURAL",
        summary: "Без творческой коррекции",
        exposure: 0,
        contrast: 1,
        highlights: 1,
        shadows: 0,
        temperature: 0,
        tint: 0,
        saturation: 1,
        vibrance: 0,
        sharpening: 0,
        noiseReduction: 0,
        vignette: 0,
        intensity: 0
    )

    static let lumoraSignature = PresetModel(
        id: "lumora-signature",
        name: "LUMORA SIGNATURE",
        summary: "Тёплый чистый цвет и мягкий контраст",
        exposure: 0.03,
        contrast: 1.07,
        highlights: 0.88,
        shadows: 0.16,
        temperature: 110,
        tint: 2,
        saturation: 1.025,
        vibrance: 0.10,
        sharpening: 0.22,
        noiseReduction: 0.08,
        vignette: 0.14,
        intensity: 1
    )

    static let balancedHDR = PresetModel(
        id: "balanced-hdr", name: "BALANCED HDR", summary: "Сбалансированные света и тени",
        exposure: 0, contrast: 1.04, highlights: 0.76, shadows: 0.27,
        temperature: 20, tint: 0, saturation: 1.01, vibrance: 0.08,
        sharpening: 0.18, noiseReduction: 0.10, vignette: 0.05, intensity: 1
    )

    static let portraitSoft = PresetModel(
        id: "portrait-soft", name: "PORTRAIT SOFT", summary: "Мягкий естественный портрет",
        exposure: 0.06, contrast: 0.98, highlights: 0.84, shadows: 0.18,
        temperature: 85, tint: 3, saturation: 0.99, vibrance: 0.05,
        sharpening: 0.08, noiseReduction: 0.12, vignette: 0.10, intensity: 1
    )

    static let nightAmber = PresetModel(
        id: "night-amber", name: "NIGHT AMBER", summary: "Тёплый ночной цвет",
        exposure: -0.04, contrast: 1.08, highlights: 0.68, shadows: 0.22,
        temperature: 180, tint: 4, saturation: 0.96, vibrance: 0.08,
        sharpening: 0.10, noiseReduction: 0.22, vignette: 0.18, intensity: 1
    )

    static let vividLandscape = PresetModel(
        id: "vivid-landscape", name: "VIVID LANDSCAPE", summary: "Насыщенный пейзаж без кислотных цветов",
        exposure: 0, contrast: 1.10, highlights: 0.78, shadows: 0.15,
        temperature: 25, tint: -2, saturation: 1.05, vibrance: 0.20,
        sharpening: 0.28, noiseReduction: 0.06, vignette: 0.08, intensity: 1
    )

    static let cinemaNoir = PresetModel(
        id: "cinema-noir", name: "CINEMA NOIR", summary: "Глубокий чёрно-белый профиль",
        exposure: -0.08, contrast: 1.20, highlights: 0.72, shadows: 0.08,
        temperature: 0, tint: 0, saturation: 0, vibrance: 0,
        sharpening: 0.20, noiseReduction: 0.05, vignette: 0.24, intensity: 1
    )

    static let emeraldStreet = PresetModel(
        id: "emerald-street", name: "EMERALD STREET", summary: "Зелёно-золотой городской профиль",
        exposure: -0.02, contrast: 1.13, highlights: 0.79, shadows: 0.12,
        temperature: 70, tint: -6, saturation: 1.02, vibrance: 0.12,
        sharpening: 0.22, noiseReduction: 0.08, vignette: 0.16, intensity: 1
    )

    static let sunsetGlow = PresetModel(
        id: "sunset-glow", name: "SUNSET GLOW", summary: "Тёплый закат с защитой светов",
        exposure: -0.03, contrast: 1.06, highlights: 0.70, shadows: 0.20,
        temperature: 220, tint: 5, saturation: 1.03, vibrance: 0.16,
        sharpening: 0.15, noiseReduction: 0.08, vignette: 0.10, intensity: 1
    )

    static let cleanSocial = PresetModel(
        id: "clean-social", name: "CLEAN SOCIAL", summary: "Светлый чистый профиль",
        exposure: 0.10, contrast: 1.03, highlights: 0.86, shadows: 0.20,
        temperature: 45, tint: 1, saturation: 1.01, vibrance: 0.09,
        sharpening: 0.16, noiseReduction: 0.10, vignette: 0, intensity: 1
    )

    static let vintage35 = PresetModel(
        id: "vintage-35", name: "VINTAGE 35", summary: "Спокойный аналоговый характер",
        exposure: 0.02, contrast: 0.94, highlights: 0.82, shadows: 0.26,
        temperature: 140, tint: 3, saturation: 0.90, vibrance: 0.04,
        sharpening: 0.07, noiseReduction: 0.04, vignette: 0.22, intensity: 1
    )

    static let detailPro = PresetModel(
        id: "detail-pro", name: "DETAIL PRO", summary: "Локальная чёткость для архитектуры",
        exposure: 0, contrast: 1.09, highlights: 0.82, shadows: 0.13,
        temperature: 0, tint: 0, saturation: 1, vibrance: 0.06,
        sharpening: 0.40, noiseReduction: 0.06, vignette: 0.04, intensity: 1
    )
}

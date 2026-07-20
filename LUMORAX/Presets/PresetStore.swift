import Combine
import Foundation

@MainActor
final class PresetStore: ObservableObject {
    @Published private(set) var presets: [PresetModel] = [
        .natural,
        .lumoraSignature,
        .balancedHDR,
        .portraitSoft,
        .nightAmber,
        .vividLandscape,
        .cinemaNoir,
        .emeraldStreet,
        .sunsetGlow,
        .cleanSocial,
        .vintage35,
        .detailPro
    ]

    @Published var selectedPresetID: PresetModel.ID {
        didSet { defaults.set(selectedPresetID, forKey: selectedPresetKey) }
    }

    var selectedPreset: PresetModel {
        presets.first(where: { $0.id == selectedPresetID }) ?? .lumoraSignature
    }

    private let defaults: UserDefaults
    private let selectedPresetKey = "presets.selectedID"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.selectedPresetID = defaults.string(forKey: selectedPresetKey)
            ?? PresetModel.lumoraSignature.id
    }
}

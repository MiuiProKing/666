import AVFoundation
import Combine
import Foundation

enum CaptureQuality: String, CaseIterable, Identifiable {
    case fast
    case balanced
    case maximum

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fast: return "Fast"
        case .balanced: return "Balanced"
        case .maximum: return "Maximum"
        }
    }

    var photoQualityPrioritization: AVCapturePhotoOutput.QualityPrioritization {
        switch self {
        case .fast: return .speed
        case .balanced: return .balanced
        case .maximum: return .quality
        }
    }
}

enum PhotoOutputFormat: String, CaseIterable, Identifiable {
    case heif
    case jpeg

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
}

@MainActor
final class AppSettings: ObservableObject {
    @Published var saveOriginal: Bool {
        didSet { defaults.set(saveOriginal, forKey: Keys.saveOriginal) }
    }

    @Published var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Keys.hapticsEnabled) }
    }

    @Published var gridEnabled: Bool {
        didSet { defaults.set(gridEnabled, forKey: Keys.gridEnabled) }
    }

    @Published var mirrorSelfie: Bool {
        didSet { defaults.set(mirrorSelfie, forKey: Keys.mirrorSelfie) }
    }

    @Published var captureQuality: CaptureQuality {
        didSet { defaults.set(captureQuality.rawValue, forKey: Keys.captureQuality) }
    }

    @Published var outputFormat: PhotoOutputFormat {
        didSet { defaults.set(outputFormat.rawValue, forKey: Keys.outputFormat) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.saveOriginal = defaults.object(forKey: Keys.saveOriginal) as? Bool ?? false
        self.hapticsEnabled = defaults.object(forKey: Keys.hapticsEnabled) as? Bool ?? true
        self.gridEnabled = defaults.object(forKey: Keys.gridEnabled) as? Bool ?? true
        self.mirrorSelfie = defaults.object(forKey: Keys.mirrorSelfie) as? Bool ?? true
        self.captureQuality = CaptureQuality(
            rawValue: defaults.string(forKey: Keys.captureQuality) ?? ""
        ) ?? .balanced
        self.outputFormat = PhotoOutputFormat(
            rawValue: defaults.string(forKey: Keys.outputFormat) ?? ""
        ) ?? .heif
    }

    private enum Keys {
        static let saveOriginal = "settings.saveOriginal"
        static let hapticsEnabled = "settings.hapticsEnabled"
        static let gridEnabled = "settings.gridEnabled"
        static let mirrorSelfie = "settings.mirrorSelfie"
        static let captureQuality = "settings.captureQuality"
        static let outputFormat = "settings.outputFormat"
    }
}

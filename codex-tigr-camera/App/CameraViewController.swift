import AVFoundation
import AudioToolbox
import CoreImage
import CoreMotion
import Photos
import PhotosUI
import UIKit
import UniformTypeIdentifiers
import Vision

private enum PhotoMode: Int, CaseIterable {
    case normal, hdr, night, portrait

    var title: String {
        switch self {
        case .normal: return "Обычный"
        case .hdr: return "HDR+"
        case .night: return "Ночь"
        case .portrait: return "Портрет"
        }
    }
}

private enum ProcessingProfile: String, Codable, CaseIterable {
    case natural = "NATURAL"
    case forestGolden = "FOREST GOLDEN"
    case cinematic = "CINEMATIC"
    case hdrNatural = "HDR NATURAL"

    var details: String {
        switch self {
        case .natural: return "Естественные цвета для людей, улицы и помещения"
        case .forestGolden: return "Тёплый свет, натуральная зелень и защищённое небо"
        case .cinematic: return "Мягкие света, глубокие тени и кинематографичный объём"
        case .hdrNatural: return "Сложный свет без ореолов и плоского изображения"
        }
    }
}

struct ProcessingSettings: Codable {
    var profile: ProcessingProfile = .natural
    var frameCount = 10
    var hdrStrength: Float = 0.72
    var denoise: Float = 0.46
    var chromaDenoise: Float = 0.48
    var sharpness: Float = 0.42
    var saturation: Float = 1.02
    var highlights: Float = 0.58
    var shadows: Float = 0.45
    var temperature: Float = 5200
    var automaticWhiteBalance = true
    var preserveSky = true
    var naturalSkin = true
    var autoScene = true
    var saveOriginal = false
    var rawEnabled = false
    var style = 0
    var manualEnabled = false
    var iso: Float = 100
    var shutterSeconds: Float = 1.0 / 60.0
    var focus: Float = 0.5
    var whiteBalance: Float = 5200
    var premiumPresetID = PremiumPresetID.fullFramePro.rawValue
    var presetIntensity: Float = 1
    var fastCapture = false
    var saveProcessed = true
    var savePNG = false
    var mirrorFront = true
    var aspectRatio = "4:3"
    var whiteBalancePreset = "Авто"

    private enum CodingKeys: String, CodingKey {
        case profile, frameCount, hdrStrength, denoise, chromaDenoise, sharpness, saturation, highlights, shadows
        case temperature, automaticWhiteBalance, preserveSky, naturalSkin, autoScene, saveOriginal, rawEnabled, style
        case manualEnabled, iso, shutterSeconds, focus, whiteBalance
        case premiumPresetID, presetIntensity, fastCapture, saveProcessed, savePNG, mirrorFront, aspectRatio, whiteBalancePreset
    }

    init() { }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profile = try c.decodeIfPresent(ProcessingProfile.self, forKey: .profile) ?? .natural
        frameCount = try c.decodeIfPresent(Int.self, forKey: .frameCount) ?? 10
        hdrStrength = try c.decodeIfPresent(Float.self, forKey: .hdrStrength) ?? 0.72
        denoise = try c.decodeIfPresent(Float.self, forKey: .denoise) ?? 0.46
        chromaDenoise = try c.decodeIfPresent(Float.self, forKey: .chromaDenoise) ?? denoise
        sharpness = try c.decodeIfPresent(Float.self, forKey: .sharpness) ?? 0.42
        saturation = try c.decodeIfPresent(Float.self, forKey: .saturation) ?? 1.02
        highlights = try c.decodeIfPresent(Float.self, forKey: .highlights) ?? 0.58
        shadows = try c.decodeIfPresent(Float.self, forKey: .shadows) ?? 0.45
        temperature = try c.decodeIfPresent(Float.self, forKey: .temperature) ?? 5200
        automaticWhiteBalance = try c.decodeIfPresent(Bool.self, forKey: .automaticWhiteBalance) ?? true
        preserveSky = try c.decodeIfPresent(Bool.self, forKey: .preserveSky) ?? true
        naturalSkin = try c.decodeIfPresent(Bool.self, forKey: .naturalSkin) ?? true
        autoScene = try c.decodeIfPresent(Bool.self, forKey: .autoScene) ?? true
        saveOriginal = try c.decodeIfPresent(Bool.self, forKey: .saveOriginal) ?? false
        rawEnabled = try c.decodeIfPresent(Bool.self, forKey: .rawEnabled) ?? false
        style = try c.decodeIfPresent(Int.self, forKey: .style) ?? 0
        manualEnabled = try c.decodeIfPresent(Bool.self, forKey: .manualEnabled) ?? false
        iso = try c.decodeIfPresent(Float.self, forKey: .iso) ?? 100
        shutterSeconds = try c.decodeIfPresent(Float.self, forKey: .shutterSeconds) ?? 1.0 / 60.0
        focus = try c.decodeIfPresent(Float.self, forKey: .focus) ?? 0.5
        whiteBalance = try c.decodeIfPresent(Float.self, forKey: .whiteBalance) ?? 5200
        premiumPresetID = try c.decodeIfPresent(String.self, forKey: .premiumPresetID) ?? PremiumPresetID.fullFramePro.rawValue
        presetIntensity = try c.decodeIfPresent(Float.self, forKey: .presetIntensity) ?? 1
        fastCapture = try c.decodeIfPresent(Bool.self, forKey: .fastCapture) ?? false
        saveProcessed = try c.decodeIfPresent(Bool.self, forKey: .saveProcessed) ?? true
        savePNG = try c.decodeIfPresent(Bool.self, forKey: .savePNG) ?? false
        mirrorFront = try c.decodeIfPresent(Bool.self, forKey: .mirrorFront) ?? true
        aspectRatio = try c.decodeIfPresent(String.self, forKey: .aspectRatio) ?? "4:3"
        whiteBalancePreset = try c.decodeIfPresent(String.self, forKey: .whiteBalancePreset) ?? "Авто"
        self = validated()
    }

    func validated() -> ProcessingSettings {
        var s = self
        s.frameCount = min(max(s.frameCount, 1), 16)
        s.hdrStrength = min(max(s.hdrStrength, 0), 1)
        s.denoise = min(max(s.denoise, 0), 1)
        s.chromaDenoise = min(max(s.chromaDenoise, 0), 1)
        s.sharpness = min(max(s.sharpness, 0), 0.75)
        s.saturation = min(max(s.saturation, 0.75), 1.25)
        s.highlights = min(max(s.highlights, 0), 1)
        s.shadows = min(max(s.shadows, 0), 1)
        s.temperature = min(max(s.temperature, 3200), 7500)
        s.focus = min(max(s.focus, 0), 1)
        s.style = min(max(s.style, 0), 3)
        s.presetIntensity = min(max(s.presetIntensity, 0), 1)
        if PremiumPresetStore.shared.preset(id: s.premiumPresetID) == nil { s.premiumPresetID = PremiumPresetID.fullFramePro.rawValue }
        if !["4:3", "16:9", "1:1"].contains(s.aspectRatio) { s.aspectRatio = "4:3" }
        if !["Авто", "Солнце", "Облачно", "Лампа", "Неон"].contains(s.whiteBalancePreset) { s.whiteBalancePreset = "Авто" }
        s.rawEnabled = false
        return s
    }

    static func preset(_ profile: ProcessingProfile, preserving source: ProcessingSettings = ProcessingSettings()) -> (ProcessingSettings, Float) {
        var s = source
        s.profile = profile
        switch profile {
        case .natural:
            s.frameCount = 10; s.hdrStrength = 0.72; s.shadows = 0.45; s.highlights = 0.58
            s.sharpness = 0.42; s.denoise = 0.46; s.chromaDenoise = 0.48; s.saturation = 1.02
            s.temperature = 5200; s.automaticWhiteBalance = true
            return (s.validated(), 0)
        case .forestGolden:
            s.frameCount = 12; s.hdrStrength = 0.84; s.shadows = 0.54; s.highlights = 0.60
            s.sharpness = 0.52; s.denoise = 0.40; s.chromaDenoise = 0.44; s.saturation = 1.12
            s.temperature = 6100; s.automaticWhiteBalance = false
            return (s.validated(), -0.08)
        case .cinematic:
            s.frameCount = 12; s.hdrStrength = 0.78; s.shadows = 0.43; s.highlights = 0.55
            s.sharpness = 0.50; s.denoise = 0.42; s.chromaDenoise = 0.44; s.saturation = 1.04
            s.temperature = 5800; s.automaticWhiteBalance = false
            return (s.validated(), -0.05)
        case .hdrNatural:
            s.frameCount = 14; s.hdrStrength = 0.88; s.shadows = 0.58; s.highlights = 0.66
            s.sharpness = 0.48; s.denoise = 0.48; s.chromaDenoise = 0.52; s.saturation = 1.06
            s.temperature = 5200; s.automaticWhiteBalance = true
            return (s.validated(), -0.03)
        }
    }

    static func load(lens: String = "1x") -> ProcessingSettings {
        let d = UserDefaults.standard
        if let data = d.data(forKey: "lens.settings.\(lens)"), let value = try? JSONDecoder().decode(ProcessingSettings.self, from: data) { return value.validated() }
        guard d.bool(forKey: "settings.saved") else { return ProcessingSettings() }
        var s = ProcessingSettings()
        s.frameCount = d.integer(forKey: "frames")
        s.hdrStrength = d.float(forKey: "hdr")
        s.denoise = d.float(forKey: "denoise")
        s.chromaDenoise = d.object(forKey: "chromaDenoise") == nil ? s.denoise : d.float(forKey: "chromaDenoise")
        s.sharpness = d.float(forKey: "sharpness")
        s.saturation = d.float(forKey: "saturation")
        s.highlights = d.float(forKey: "highlights")
        s.shadows = d.float(forKey: "shadows")
        s.temperature = d.float(forKey: "temperature")
        s.preserveSky = d.bool(forKey: "sky")
        s.naturalSkin = d.bool(forKey: "skin")
        s.saveOriginal = d.bool(forKey: "original")
        s.rawEnabled = d.bool(forKey: "raw")
        s.style = d.integer(forKey: "style")
        s.manualEnabled = d.bool(forKey: "manual")
        s.iso = d.float(forKey: "iso")
        s.shutterSeconds = d.float(forKey: "shutter")
        s.focus = d.float(forKey: "focus")
        s.whiteBalance = d.float(forKey: "wb")
        return s.validated()
    }

    func save(lens: String = "1x") {
        let d = UserDefaults.standard
        let safe = validated()
        if let data = try? JSONEncoder().encode(safe) { d.set(data, forKey: "lens.settings.\(lens)") }
        d.set(true, forKey: "settings.saved")
        d.set(frameCount, forKey: "frames")
        d.set(hdrStrength, forKey: "hdr")
        d.set(denoise, forKey: "denoise")
        d.set(chromaDenoise, forKey: "chromaDenoise")
        d.set(sharpness, forKey: "sharpness")
        d.set(saturation, forKey: "saturation")
        d.set(highlights, forKey: "highlights")
        d.set(shadows, forKey: "shadows")
        d.set(temperature, forKey: "temperature")
        d.set(preserveSky, forKey: "sky")
        d.set(naturalSkin, forKey: "skin")
        d.set(saveOriginal, forKey: "original")
        d.set(rawEnabled, forKey: "raw")
        d.set(style, forKey: "style")
        d.set(manualEnabled, forKey: "manual")
        d.set(iso, forKey: "iso")
        d.set(shutterSeconds, forKey: "shutter")
        d.set(focus, forKey: "focus")
        d.set(whiteBalance, forKey: "wb")
    }
}

private struct TigrConfig: Codable {
    var name: String?
    var type: String?
    var profile: ProcessingProfile?
    var frames: Int?
    var exposure: Float?
    var hdrStrength: Float?
    var shadows: Float?
    var highlights: Float?
    var sharpness: Float?
    var noiseReduction: Float?
    var saturation: Float?
    var temperature: Float?
    var preserveSky: Bool?
    var naturalSkin: Bool?
    var chromaNoiseReduction: Float?
    var autoScene: Bool?

    init(settings: ProcessingSettings, exposure: Float, name: String = "Tigr Style") {
        self.name = name; type = "photo"; profile = settings.profile; frames = settings.frameCount; self.exposure = exposure; hdrStrength = settings.hdrStrength
        shadows = settings.shadows; highlights = settings.highlights; sharpness = settings.sharpness
        noiseReduction = settings.denoise; saturation = settings.saturation; temperature = settings.temperature
        preserveSky = settings.preserveSky; naturalSkin = settings.naturalSkin; chromaNoiseReduction = settings.chromaDenoise; autoScene = settings.autoScene
    }

    func applied(to source: ProcessingSettings) -> ProcessingSettings {
        var s = source
        if let profile { s.profile = profile }
        if let frames { s.frameCount = frames }
        if let hdrStrength { s.hdrStrength = hdrStrength }
        if let shadows { s.shadows = shadows }
        if let highlights { s.highlights = highlights }
        if let sharpness { s.sharpness = sharpness }
        if let noiseReduction { s.denoise = noiseReduction }
        if let chromaNoiseReduction { s.chromaDenoise = chromaNoiseReduction }
        if let saturation { s.saturation = saturation }
        if let temperature { s.temperature = temperature; s.automaticWhiteBalance = false }
        if let preserveSky { s.preserveSky = preserveSky }
        if let naturalSkin { s.naturalSkin = naturalSkin }
        if let autoScene { s.autoScene = autoScene }
        return s.validated()
    }
}

private enum PhotoScene: String {
    case person = "Портрет", forest = "Лес", nature = "Природа", sunset = "Закат", sky = "Небо"
    case city = "Город", indoor = "Помещение", night = "Ночь", screen = "Экран", vehicle = "Транспорт"
    case animal = "Животное", architecture = "Архитектура", general = "Обычная"
}

private struct PhotoProcessingContext {
    let scene: PhotoScene
    let brightness: Float
    let dynamicRange: Float
    let iso: Float
    let flash: Bool
    let stable: Bool
    let lens: String
    let frontCamera: Bool
}

private enum VideoProfile: String, Codable, CaseIterable {
    case natural = "VIDEO NATURAL", forestGolden = "VIDEO FOREST GOLDEN", cinematic = "VIDEO CINEMATIC"
    case hdrNatural = "VIDEO HDR NATURAL", lowLight = "VIDEO LOW LIGHT"
}

private enum VideoQuality: String, Codable, CaseIterable { case standard = "STANDARD", high = "HIGH", max = "MAX" }
private enum VideoCodec: String, Codable, CaseIterable { case hevc, h264 }
private enum VideoStabilization: String, Codable, CaseIterable { case off, standard, cinematic, auto }
private enum VideoPreset: String, Codable, CaseIterable {
    case max4K = "4K MAX QUALITY", smooth4K = "4K SMOOTH", cinema24 = "CINEMA 24"
    case lowLight = "LOW LIGHT", longRecord = "LONG RECORD", social = "SOCIAL"
}

private struct VideoSettings: Codable {
    var preset: VideoPreset = .max4K
    var profile: VideoProfile = .natural
    var resolution = "3840x2160"
    var fps = 30
    var codec: VideoCodec = .hevc
    var quality: VideoQuality = .high
    var bitrateMbps: Float = 80
    var hdrEnabled = false
    var stabilization: VideoStabilization = .auto
    var exposure: Float = 0
    var saturation: Float = 1.02
    var temperature: Float = 5200
    var sharpness: Float = 0.35
    var noiseReduction: Float = 0.35
    var chromaNoiseReduction: Float = 0.42
    var naturalSkin = true
    var preserveSky = true
    var whiteBalanceLock = false
    var exposureLock = false
    var focusLock = false
    var manualEnabled = false
    var iso: Float = 100
    var shutterSeconds: Float = 1.0 / 60.0
    var focus: Float = 0.5
    var tint: Float = 0
    var exposureSmoothing = true
    var audioSampleRate = 48_000
    var audioBitrateKbps = 256

    static func load() -> VideoSettings {
        guard let data = UserDefaults.standard.data(forKey: "tigr.video.settings"), let value = try? JSONDecoder().decode(VideoSettings.self, from: data) else { return VideoSettings() }
        return value.validated()
    }

    func save() { if let data = try? JSONEncoder().encode(validated()) { UserDefaults.standard.set(data, forKey: "tigr.video.settings") } }

    func validated() -> VideoSettings {
        var s = self
        if !["1280x720", "1920x1080", "3840x2160"].contains(s.resolution) { s.resolution = "1920x1080" }
        if ![24, 25, 30, 50, 60].contains(s.fps) { s.fps = 30 }
        s.bitrateMbps = min(max(s.bitrateMbps, 8), 220)
        s.exposure = min(max(s.exposure, -1), 1)
        s.saturation = min(max(s.saturation, 0.80), 1.20)
        s.temperature = min(max(s.temperature, 3200), 7500)
        s.sharpness = min(max(s.sharpness, 0), 0.60)
        s.noiseReduction = min(max(s.noiseReduction, 0), 1)
        s.chromaNoiseReduction = min(max(s.chromaNoiseReduction, 0), 1)
        s.audioSampleRate = 48_000
        s.audioBitrateKbps = min(max(s.audioBitrateKbps, 96), 320)
        s.iso = min(max(s.iso, 25), 6400)
        s.shutterSeconds = min(max(s.shutterSeconds, 1.0 / 16_000.0), 1)
        s.focus = min(max(s.focus, 0), 1)
        s.tint = min(max(s.tint, -100), 100)
        return s
    }

    static func settings(for preset: VideoPreset) -> VideoSettings {
        var s = VideoSettings(); s.preset = preset
        switch preset {
        case .max4K: s.resolution = "3840x2160"; s.fps = 30; s.codec = .hevc; s.quality = .max; s.bitrateMbps = 120
        case .smooth4K: s.resolution = "3840x2160"; s.fps = 60; s.codec = .hevc; s.quality = .high; s.bitrateMbps = 120
        case .cinema24: s.resolution = "3840x2160"; s.fps = 24; s.codec = .hevc; s.quality = .high; s.bitrateMbps = 80; s.profile = .cinematic; s.whiteBalanceLock = true; s.manualEnabled = true; s.shutterSeconds = 1.0 / 48.0
        case .lowLight: s.resolution = "1920x1080"; s.fps = 30; s.codec = .hevc; s.quality = .high; s.bitrateMbps = 28; s.profile = .lowLight
        case .longRecord: s.resolution = "1920x1080"; s.fps = 30; s.codec = .hevc; s.quality = .standard; s.bitrateMbps = 16
        case .social: s.resolution = "1920x1080"; s.fps = 30; s.codec = .h264; s.quality = .high; s.bitrateMbps = 22
        }
        return s
    }
}

private struct TigrVideoConfig: Codable {
    var name: String?
    var type: String?
    var resolution: String?
    var fps: Int?
    var codec: VideoCodec?
    var quality: VideoQuality?
    var bitrateMbps: Float?
    var hdrEnabled: Bool?
    var stabilization: VideoStabilization?
    var exposure: Float?
    var saturation: Float?
    var temperature: Float?
    var sharpness: Float?
    var noiseReduction: Float?
    var chromaNoiseReduction: Float?
    var naturalSkin: Bool?
    var preserveSky: Bool?
    var whiteBalanceLock: Bool?
    var manualEnabled: Bool?
    var iso: Float?
    var shutterSeconds: Float?
    var focus: Float?
    var tint: Float?
    var exposureSmoothing: Bool?
    var audioSampleRate: Int?
    var audioBitrateKbps: Int?

    init(settings s: VideoSettings, name: String = "Tigr Video Profile") {
        self.name = name; type = "video"; resolution = s.resolution; fps = s.fps; codec = s.codec; quality = s.quality
        bitrateMbps = s.bitrateMbps; hdrEnabled = s.hdrEnabled; stabilization = s.stabilization; exposure = s.exposure
        saturation = s.saturation; temperature = s.temperature; sharpness = s.sharpness; noiseReduction = s.noiseReduction
        chromaNoiseReduction = s.chromaNoiseReduction; naturalSkin = s.naturalSkin; preserveSky = s.preserveSky
        whiteBalanceLock = s.whiteBalanceLock; exposureSmoothing = s.exposureSmoothing
        manualEnabled = s.manualEnabled; iso = s.iso; shutterSeconds = s.shutterSeconds; focus = s.focus; tint = s.tint
        audioSampleRate = s.audioSampleRate; audioBitrateKbps = s.audioBitrateKbps
    }

    func applied(to source: VideoSettings) -> VideoSettings {
        var s = source
        if let resolution { s.resolution = resolution }; if let fps { s.fps = fps }; if let codec { s.codec = codec }
        if let quality { s.quality = quality }; if let bitrateMbps { s.bitrateMbps = bitrateMbps }; if let hdrEnabled { s.hdrEnabled = hdrEnabled }
        if let stabilization { s.stabilization = stabilization }; if let exposure { s.exposure = exposure }; if let saturation { s.saturation = saturation }
        if let temperature { s.temperature = temperature }; if let sharpness { s.sharpness = sharpness }
        if let noiseReduction { s.noiseReduction = noiseReduction }; if let chromaNoiseReduction { s.chromaNoiseReduction = chromaNoiseReduction }
        if let naturalSkin { s.naturalSkin = naturalSkin }; if let preserveSky { s.preserveSky = preserveSky }
        if let whiteBalanceLock { s.whiteBalanceLock = whiteBalanceLock }; if let exposureSmoothing { s.exposureSmoothing = exposureSmoothing }…26602 tokens truncated…der("Выдержка", 1.0/8000.0, 1, settings.shutterSeconds, valueText: { $0 >= 0.5 ? String(format: "%.1f с", $0) : "1/\(max(1, Int(1 / $0))) с" }) { self.settings.shutterSeconds = $0 }
        addSlider("Ручной фокус", 0, 1, settings.focus) { self.settings.focus = $0 }
        addSlider("Баланс белого", 3000, 8500, settings.whiteBalance, valueText: { "\(Int($0)) K" }) { self.settings.whiteBalance = $0 }

        addHeader("VIDEO PRO")
        let videoHint = UILabel(); videoHint.numberOfLines = 0; videoHint.font = .systemFont(ofSize: 12); videoHint.textColor = .secondaryLabel; videoHint.text = "Показываются только режимы, найденные через AVFoundation на текущем объективе."; stack.addArrangedSubview(videoHint)
        addMenuButton(title: "Готовый режим: \(videoSettings.preset.rawValue)", items: VideoPreset.allCases.map(\.rawValue)) { [weak self] index, button in
            guard let self else { return }; let preset = VideoPreset.allCases[index]; self.videoSettings = VideoSettings.settings(for: preset); button.setTitle("Готовый режим: \(preset.rawValue)", for: .normal)
        }
        let uniqueModes = videoModes.reduce(into: [VideoMode]()) { list, mode in if !list.contains(where: { $0.resolution == mode.resolution && $0.fps == mode.fps }) { list.append(mode) } }
        addMenuButton(title: "Формат: \(videoSettings.resolution) • \(videoSettings.fps) FPS", items: uniqueModes.map(\.title)) { [weak self] index, button in
            guard let self, uniqueModes.indices.contains(index) else { return }; let mode = uniqueModes[index]; self.videoSettings.resolution = mode.resolution; self.videoSettings.fps = mode.fps; button.setTitle("Формат: \(mode.title)", for: .normal)
        }
        addMenuButton(title: "Профиль: \(videoSettings.profile.rawValue)", items: VideoProfile.allCases.map(\.rawValue)) { [weak self] index, button in
            guard let self else { return }; self.videoSettings.profile = VideoProfile.allCases[index]; button.setTitle("Профиль: \(self.videoSettings.profile.rawValue)", for: .normal)
        }
        let codecs = UISegmentedControl(items: ["HEVC", "H.264"]); codecs.selectedSegmentIndex = videoSettings.codec == .hevc ? 0 : 1; codecs.addAction(UIAction { [weak self] _ in self?.videoSettings.codec = codecs.selectedSegmentIndex == 0 ? .hevc : .h264 }, for: .valueChanged); stack.addArrangedSubview(codecs)
        let qualities = UISegmentedControl(items: VideoQuality.allCases.map(\.rawValue)); qualities.selectedSegmentIndex = VideoQuality.allCases.firstIndex(of: videoSettings.quality) ?? 1; qualities.addAction(UIAction { [weak self] _ in self?.videoSettings.quality = VideoQuality.allCases[qualities.selectedSegmentIndex] }, for: .valueChanged); stack.addArrangedSubview(qualities)
        addSlider("Битрейт видео", 8, 220, videoSettings.bitrateMbps, valueText: { "\(Int($0)) Мбит/с" }) { self.videoSettings.bitrateMbps = $0 }
        addSwitch("HDR VIDEO (только если поддерживается)", videoSettings.hdrEnabled) { self.videoSettings.hdrEnabled = $0 }
        let stabilizations = UISegmentedControl(items: ["OFF", "STD", "CINEMA", "AUTO"]); stabilizations.selectedSegmentIndex = VideoStabilization.allCases.firstIndex(of: videoSettings.stabilization) ?? 3; stabilizations.addAction(UIAction { [weak self] _ in self?.videoSettings.stabilization = VideoStabilization.allCases[stabilizations.selectedSegmentIndex] }, for: .valueChanged); stack.addArrangedSubview(stabilizations)
        addSwitch("WB LOCK", videoSettings.whiteBalanceLock) { self.videoSettings.whiteBalanceLock = $0 }
        addSwitch("EXPOSURE LOCK", videoSettings.exposureLock) { self.videoSettings.exposureLock = $0 }
        addSwitch("FOCUS LOCK", videoSettings.focusLock) { self.videoSettings.focusLock = $0 }
        addSwitch("Ручной VIDEO PRO", videoSettings.manualEnabled) { self.videoSettings.manualEnabled = $0 }
        addSlider("ISO видео", 25, 6400, videoSettings.iso, valueText: { "\(Int($0))" }) { self.videoSettings.iso = $0 }
        addSlider("Выдержка видео", 1.0/16000.0, 1.0/24.0, videoSettings.shutterSeconds, valueText: { "1/\(max(1, Int(1 / $0)))" }) { self.videoSettings.shutterSeconds = $0 }
        addSlider("Фокус видео", 0, 1, videoSettings.focus) { self.videoSettings.focus = $0 }
        addSlider("Температура видео", 3200, 7500, videoSettings.temperature, valueText: { "\(Int($0)) K" }) { self.videoSettings.temperature = $0 }
        addSlider("Tint видео", -100, 100, videoSettings.tint, valueText: { String(format: "%+.0f", $0) }) { self.videoSettings.tint = $0 }
        addSlider("Насыщенность видео", 0.80, 1.20, videoSettings.saturation) { self.videoSettings.saturation = $0 }
        addSlider("Резкость видео", 0, 0.60, videoSettings.sharpness) { self.videoSettings.sharpness = $0 }
        addSlider("Шумоподавление видео", 0, 1, videoSettings.noiseReduction) { self.videoSettings.noiseReduction = $0 }
        let audioInputs = AVAudioSession.sharedInstance().availableInputs ?? []
        if !audioInputs.isEmpty {
            addMenuButton(title: "Аудиовход: \(AVAudioSession.sharedInstance().preferredInput?.portName ?? "Авто")", items: audioInputs.map(\.portName)) { index, button in
                guard audioInputs.indices.contains(index) else { return }; try? AVAudioSession.sharedInstance().setPreferredInput(audioInputs[index]); button.setTitle("Аудиовход: \(audioInputs[index].portName)", for: .normal)
            }
        }
        let reset = UIButton(type: .system); reset.setTitle("СБРОСИТЬ ФОТО И ВИДЕО В АВТО", for: .normal); reset.setTitleColor(.systemRed, for: .normal); reset.addAction(UIAction { [weak self] _ in guard let self else { return }; self.settings = ProcessingSettings.preset(.natural).0; self.videoSettings = VideoSettings(); self.exposure = 0 }, for: .touchUpInside); stack.addArrangedSubview(reset)
    }

    private func addHeader(_ text: String) { let label = UILabel(); label.text = text; label.font = .systemFont(ofSize: 18, weight: .bold); label.textColor = .label; stack.addArrangedSubview(label) }

    private func addSwitch(_ title: String, _ value: Bool, enabled: Bool = true, change: @escaping (Bool) -> Void) {
        let row = UIStackView(); row.axis = .horizontal
        let label = UILabel(); label.text = title; label.font = .systemFont(ofSize: 15); label.numberOfLines = 2
        let control = UISwitch(); control.isOn = value; control.isEnabled = enabled; control.addAction(UIAction { _ in change(control.isOn) }, for: .valueChanged)
        row.addArrangedSubview(label); row.addArrangedSubview(control); stack.addArrangedSubview(row)
    }

    private func addSlider(_ title: String, _ min: Float, _ max: Float, _ value: Float, valueText: @escaping (Float) -> String = { String(format: "%.2f", $0) }, change: @escaping (Float) -> Void) {
        let label = UILabel(); label.font = .systemFont(ofSize: 14, weight: .medium); label.text = "\(title): \(valueText(value))"; stack.addArrangedSubview(label)
        let slider = UISlider(); slider.minimumValue = min; slider.maximumValue = max; slider.value = value; slider.minimumTrackTintColor = UIColor(red: 0.95, green: 0.62, blue: 0.08, alpha: 1)
        slider.addAction(UIAction { _ in label.text = "\(title): \(valueText(slider.value))"; change(slider.value) }, for: .valueChanged); stack.addArrangedSubview(slider)
    }

    private func addMenuButton(title: String, items: [String], selection: @escaping (Int, UIButton) -> Void) {
        let button = UIButton(type: .system); button.contentHorizontalAlignment = .leading; button.setTitle(title, for: .normal)
        button.showsMenuAsPrimaryAction = true
        button.menu = UIMenu(children: items.enumerated().map { index, item in UIAction(title: item) { _ in selection(index, button) } })
        stack.addArrangedSubview(button)
    }

    @objc private func importConfig() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json], asCopy: true); picker.delegate = self; present(picker, animated: true)
    }

    @objc private func exportConfig() {
        let config = TigrConfig(settings: settings, exposure: exposure, name: "Tigr Style \(lensName)")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Tigr-Style-\(lensName).json")
        do { try data.write(to: url, options: .atomic); present(UIActivityViewController(activityItems: [url], applicationActivities: nil), animated: true) } catch { }
    }

    @objc private func exportVideoConfig() {
        let config = TigrVideoConfig(settings: videoSettings, name: "Tigr Video \(videoSettings.profile.rawValue)")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Tigr-Video-Profile.json")
        do { try data.write(to: url, options: .atomic); present(UIActivityViewController(activityItems: [url], applicationActivities: nil), animated: true) }
        catch { showAlert(title: "Ошибка", message: "Не удалось экспортировать видеопрофиль.") }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first, let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            showAlert(title: "Повреждённый JSON", message: "Файл не является корректным JSON-профилем Tigr."); return
        }
        let type = (object["type"] as? String)?.lowercased() ?? "photo"
        if type == "video" {
            guard let config = try? JSONDecoder().decode(TigrVideoConfig.self, from: data) else { showAlert(title: "Ошибка видеопрофиля", message: "Структура видеопрофиля повреждена."); return }
            var imported = config.applied(to: videoSettings)
            if let fallback = VideoModeDiscovery.closest(to: imported, in: videoModes) { imported.resolution = fallback.resolution; imported.fps = fallback.fps }
            else { imported.resolution = "1920x1080"; imported.fps = 30 }
            videoSettings = imported.validated()
            showAlert(title: "Видеопрофиль импортирован", message: "\(config.name ?? "Tigr Video") проверен и применён. Неподдерживаемые значения заменены безопасными.")
        } else {
            guard let config = try? JSONDecoder().decode(TigrConfig.self, from: data) else { showAlert(title: "Ошибка фотопрофиля", message: "Структура фотопрофиля повреждена."); return }
            settings = config.applied(to: settings)
            if let importedExposure = config.exposure { exposure = min(max(importedExposure, -1), 1) }
            showAlert(title: "Фотопрофиль импортирован", message: "\(config.name ?? "Tigr Photo") применён к объективу \(lensName). Все значения ограничены безопасными пределами.")
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert); alert.addAction(UIAlertAction(title: "OK", style: .default)); present(alert, animated: true)
    }

    @objc private func done() { onSave?(settings.validated(), videoSettings.validated(), min(max(exposure, -1), 1)); dismiss(animated: true) }
}

private enum VideoModeDiscovery {
    static func modes(for device: AVCaptureDevice) -> [VideoMode] {
        let allowed: [String: CMVideoDimensions] = [
            "1280x720": .init(width: 1280, height: 720),
            "1920x1080": .init(width: 1920, height: 1080),
            "3840x2160": .init(width: 3840, height: 2160)
        ]
        let fpsValues = [24, 25, 30, 50, 60]
        var result: [VideoMode] = []
        for format in device.formats {
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard let resolution = allowed.first(where: { $0.value.width == dimensions.width && $0.value.height == dimensions.height })?.key else { continue }
            for fps in fpsValues where format.videoSupportedFrameRateRanges.contains(where: { Double(fps) >= $0.minFrameRate - 0.01 && Double(fps) <= $0.maxFrameRate + 0.01 }) {
                result.append(VideoMode(resolution: resolution, fps: fps, format: format))
            }
        }
        return result.sorted {
            let area0 = resolutionArea($0.resolution), area1 = resolutionArea($1.resolution)
            return area0 == area1 ? $0.fps < $1.fps : area0 < area1
        }
    }

    static func closest(to settings: VideoSettings, in modes: [VideoMode]) -> VideoMode? {
        let exact = modes.filter { $0.resolution == settings.resolution && $0.fps == settings.fps }
        if let hdrExact = exact.first(where: { !settings.hdrEnabled || $0.format.isVideoHDRSupported }) { return hdrExact }
        return modes.min {
            score($0, target: settings) < score($1, target: settings)
        }
    }

    private static func score(_ mode: VideoMode, target: VideoSettings) -> Int {
        abs(resolutionArea(mode.resolution) - resolutionArea(target.resolution)) / 100_000 + abs(mode.fps - target.fps) * 8
    }

    private static func resolutionArea(_ value: String) -> Int {
        switch value { case "3840x2160": return 8_294_400; case "1920x1080": return 2_073_600; default: return 921_600 }
    }
}

private enum TigrValidationTests {
    static func run() -> Bool {
        var photo = ProcessingSettings(); photo.frameCount = 99; photo.sharpness = 9; photo.saturation = -4
        let safePhoto = photo.validated()
        guard safePhoto.frameCount == 16, safePhoto.sharpness == 0.75, safePhoto.saturation == 0.75 else { return false }
        var video = VideoSettings(); video.resolution = "broken"; video.fps = 999; video.bitrateMbps = 900
        let safeVideo = video.validated()
        guard safeVideo.resolution == "1920x1080", safeVideo.fps == 30, safeVideo.bitrateMbps == 220 else { return false }
        let broken = Data("{broken".utf8)
        guard (try? JSONDecoder().decode(TigrConfig.self, from: broken)) == nil else { return false }
        return true
    }
}

private enum DeviceInfo {
    static func machine() -> String { var info = utsname(); uname(&info); return withUnsafePointer(to: &info.machine) { $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) } } }
    static func hasLens(_ type: AVCaptureDevice.DeviceType) -> Bool { !AVCaptureDevice.DiscoverySession(deviceTypes: [type], mediaType: .video, position: .back).devices.isEmpty }
    static func shortSummary(photoOutput: AVCapturePhotoOutput) -> String { "\(machine()) • iPhone 12 • 0.5× / 1× • PNG" }
    static func summary(photoOutput: AVCapturePhotoOutput) -> String {
        "Устройство: \(machine())\nПрофиль: стандартный iPhone 12\nКамеры: 0.5× \(hasLens(.builtInUltraWideCamera) ? "доступна" : "недоступна") • 1× доступна • фронтальная доступна\nТелефото/LiDAR/ProRAW: недоступны • Портрет: программное размытие\nЭкспорт: JPEG или PNG в настройках"
    }
}

private final class AudioLevelMonitor: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let callback: (Float) -> Void
    private var lastUpdate = CFAbsoluteTimeGetCurrent()
    init(callback: @escaping (Float) -> Void) { self.callback = callback }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = CFAbsoluteTimeGetCurrent(); guard now - lastUpdate > 0.08 else { return }; lastUpdate = now
        guard let block = CMSampleBufferGetDataBuffer(sampleBuffer), let format = CMSampleBufferGetFormatDescription(sampleBuffer),
              let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee else { return }
        var lengthAtOffset = 0, totalLength = 0, pointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset, totalLengthOut: &totalLength, dataPointerOut: &pointer) == kCMBlockBufferNoErr,
              let pointer, totalLength > 0 else { return }
        var rms: Double = 0
        if description.mBitsPerChannel == 32 && (description.mFormatFlags & kAudioFormatFlagIsFloat) != 0 {
            let count = totalLength / MemoryLayout<Float>.size
            let samples = UnsafeRawPointer(pointer).assumingMemoryBound(to: Float.self)
            let stride = max(1, count / 512)
            var used = 0
            for index in Swift.stride(from: 0, to: count, by: stride) { let value = Double(samples[index]); rms += value * value; used += 1 }
            rms = used > 0 ? sqrt(rms / Double(used)) : 0
        } else {
            let count = totalLength / MemoryLayout<Int16>.size
            let samples = UnsafeRawPointer(pointer).assumingMemoryBound(to: Int16.self)
            let stride = max(1, count / 512)
            var used = 0
            for index in Swift.stride(from: 0, to: count, by: stride) { let value = Double(samples[index]) / 32768.0; rms += value * value; used += 1 }
            rms = used > 0 ? sqrt(rms / Double(used)) : 0
        }
        let normalized = Float(min(1, max(0, (20 * log10(max(rms, 0.000_01)) + 55) / 55)))
        DispatchQueue.main.async { self.callback(normalized) }
    }
}

extension CameraViewController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async { self.setRecordingUI(active: false) }
        guard error == nil else { try? FileManager.default.removeItem(at: outputFileURL); DispatchQueue.main.async { self.showStatus("Ошибка записи") }; return }
        DispatchQueue.main.async { self.showStatus(self.videoSettings.hdrEnabled ? "Финализация HDR-видео…" : "Обработка видеопрофиля…") }
        VideoPostProcessor.process(outputFileURL, settings: videoSettings, thermalState: lastThermalState) { [weak self] finalURL in self?.saveVideo(finalURL) }
    }
}

extension CameraViewController: PHPickerViewControllerDelegate { func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) { picker.dismiss(animated: true) } }

private final class GridOverlayView: UIView {
    override class var layerClass: AnyClass { CAShapeLayer.self }
    override func layoutSubviews() {
        super.layoutSubviews(); guard let shape = layer as? CAShapeLayer else { return }; let path = UIBezierPath()
        for f in [CGFloat(1.0/3.0), CGFloat(2.0/3.0)] { path.move(to: .init(x: bounds.width*f, y: 0)); path.addLine(to: .init(x: bounds.width*f, y: bounds.height)); path.move(to: .init(x: 0, y: bounds.height*f)); path.addLine(to: .init(x: bounds.width, y: bounds.height*f)) }
        shape.path = path.cgPath; shape.strokeColor = UIColor.white.withAlphaComponent(0.34).cgColor; shape.fillColor = UIColor.clear.cgColor; shape.lineWidth = 0.7
    }
}


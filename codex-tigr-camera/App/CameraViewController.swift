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
        if let whiteBalanceLock { s.whiteBalanceLock = whiteBalanceLock }; if let exposureSmoothing { s.exposureSmoothing = exposureSmoothing }
        if let manualEnabled { s.manualEnabled = manualEnabled }; if let iso { s.iso = iso }; if let shutterSeconds { s.shutterSeconds = shutterSeconds }; if let focus { s.focus = focus }; if let tint { s.tint = tint }
        if let audioSampleRate { s.audioSampleRate = audioSampleRate }; if let audioBitrateKbps { s.audioBitrateKbps = audioBitrateKbps }
        return s.validated()
    }
}

private struct VideoMode: Equatable {
    let resolution: String
    let fps: Int
    let format: AVCaptureDevice.Format
    var title: String { "\(resolution == "3840x2160" ? "4K" : (resolution == "1920x1080" ? "1080p" : "720p")) \(fps) FPS" }
}

private struct CapturedFrame {
    let image: UIImage
    let originalData: Data
    let rawData: Data?
    let metadata: [String: Any]
    let flashFired: Bool
}

private final class SeriesAccumulator { var frames: [CapturedFrame] = [] }

final class CameraViewController: UIViewController {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.tigr.camera.session", qos: .userInitiated)
    private let processingQueue = DispatchQueue(label: "com.tigr.camera.processing", qos: .userInitiated)
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let audioMeterOutput = AVCaptureAudioDataOutput()
    private lazy var audioLevelMonitor = AudioLevelMonitor { [weak self] level in
        guard let self else { return }
        let bars = min(8, max(0, Int(level * 9)))
        self.audioLevelLabel.text = " MIC " + String(repeating: "▮", count: bars) + String(repeating: "▯", count: 8 - bars) + (level > 0.92 ? "  ПЕРЕГРУЗКА" : "")
        self.audioLevelLabel.textColor = level > 0.92 ? .systemRed : .systemGreen
    }
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var isConfigured = false
    private var photoMode: PhotoMode = .normal
    private var isVideoMode = false
    private var flashMode: AVCaptureDevice.FlashMode = .off
    private var timerSeconds = 0
    private var gridVisible = true
    private var countdownTimer: Timer?
    private var recordingStartedAt: Date?
    private var recordingTimer: Timer?
    private var currentLensKey = "1x"
    private var settings = ProcessingSettings.load(lens: "1x")
    private var videoSettings = VideoSettings.load()
    private var availableVideoModes: [VideoMode] = []
    private let motionManager = CMMotionManager()
    private var isDeviceStable = true
    private var lastThermalState = ProcessInfo.processInfo.thermalState
    private var activeDelegates: [UUID: FrameCaptureDelegate] = [:]
    private var isCapturingSeries = false

    private let previewView = UIView()
    private lazy var previewLayer = AVCaptureVideoPreviewLayer(session: session)
    private let topBar = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let bottomBar = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let flashButton = UIButton(type: .system)
    private let timerButton = UIButton(type: .system)
    private let gridButton = UIButton(type: .system)
    private let videoButton = UIButton(type: .system)
    private let settingsButton = UIButton(type: .system)
    private let switchButton = UIButton(type: .system)
    private let galleryButton = UIButton(type: .system)
    private let shutterButton = UIButton(type: .custom)
    private let modeControl = UISegmentedControl(items: PhotoMode.allCases.map(\.title))
    private let exposureSlider = UISlider()
    private let exposureLabel = UILabel()
    private let countdownLabel = UILabel()
    private let recordingLabel = UILabel()
    private let profileLabel = UILabel()
    private let videoInfoLabel = UILabel()
    private let storageLabel = UILabel()
    private let audioLevelLabel = UILabel()
    private let statusLabel = UILabel()
    private let gridView = GridOverlayView()
    private let focusRing = UIView()
    private let zoomStack = UIStackView()
    private let presetScroll = UIScrollView()
    private let presetStack = UIStackView()
    private let previewTintView = UIView()
    private let previewVignette = CAGradientLayer()
    private let levelView = UIView()
    private var presetButtons: [String: UIButton] = [:]

    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        buildInterface()
        startMotionMonitoring()
        NotificationCenter.default.addObserver(self, selector: #selector(thermalStateChanged), name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
        requestCameraPermission()
    }

    deinit {
        motionManager.stopDeviceMotionUpdates()
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startSessionIfPossible()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = previewView.bounds
        previewLayer.videoGravity = .resizeAspectFill
        previewVignette.frame = previewTintView.bounds
        previewVignette.startPoint = CGPoint(x: 0.5, y: 0.5)
        previewVignette.endPoint = CGPoint(x: 1.0, y: 1.0)
    }

    private func buildInterface() {
        previewView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewView)
        previewView.layer.addSublayer(previewLayer)
        previewTintView.translatesAutoresizingMaskIntoConstraints = false
        previewTintView.isUserInteractionEnabled = false
        previewView.addSubview(previewTintView)
        previewVignette.type = .radial
        previewVignette.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.28).cgColor]
        previewVignette.locations = [0.50, 1.0]
        previewVignette.isHidden = true
        previewTintView.layer.addSublayer(previewVignette)
        gridView.translatesAutoresizingMaskIntoConstraints = false
        gridView.isUserInteractionEnabled = false
        previewView.addSubview(gridView)

        topBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topBar)
        view.addSubview(bottomBar)

        let topStack = UIStackView()
        topStack.translatesAutoresizingMaskIntoConstraints = false
        topStack.axis = .horizontal
        topStack.distribution = .equalSpacing
        [flashButton, timerButton, gridButton, videoButton, settingsButton].forEach { topStack.addArrangedSubview($0) }
        topBar.contentView.addSubview(topStack)
        configureTopButton(flashButton, image: "bolt.slash.fill", action: #selector(toggleFlash))
        configureTopButton(timerButton, image: "timer", action: #selector(toggleTimer))
        configureTopButton(gridButton, image: "grid", action: #selector(toggleGrid))
        configureTopButton(videoButton, image: "video.fill", action: #selector(toggleVideoMode))
        configureTopButton(settingsButton, image: "slider.horizontal.3", action: #selector(openSettings))

        presetScroll.translatesAutoresizingMaskIntoConstraints = false
        presetScroll.showsHorizontalScrollIndicator = false
        presetScroll.alwaysBounceHorizontal = true
        bottomBar.contentView.addSubview(presetScroll)
        presetStack.translatesAutoresizingMaskIntoConstraints = false
        presetStack.axis = .horizontal
        presetStack.spacing = 10
        presetStack.alignment = .top
        presetScroll.addSubview(presetStack)
        rebuildPresetCarousel()

        modeControl.translatesAutoresizingMaskIntoConstraints = false
        modeControl.selectedSegmentIndex = 0
        modeControl.selectedSegmentTintColor = UIColor(red: 0.98, green: 0.74, blue: 0.18, alpha: 1)
        modeControl.setTitleTextAttributes([.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 11)], for: .normal)
        modeControl.setTitleTextAttributes([.foregroundColor: UIColor.black, .font: UIFont.boldSystemFont(ofSize: 11)], for: .selected)
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        bottomBar.contentView.addSubview(modeControl)

        exposureLabel.translatesAutoresizingMaskIntoConstraints = false
        exposureLabel.text = "EV 0.0"
        exposureLabel.textColor = .white
        exposureLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        bottomBar.contentView.addSubview(exposureLabel)
        exposureSlider.translatesAutoresizingMaskIntoConstraints = false
        exposureSlider.minimumValue = -2
        exposureSlider.maximumValue = 2
        exposureSlider.minimumTrackTintColor = UIColor(red: 0.98, green: 0.74, blue: 0.18, alpha: 1)
        exposureSlider.addTarget(self, action: #selector(exposureChanged), for: .valueChanged)
        bottomBar.contentView.addSubview(exposureSlider)

        shutterButton.translatesAutoresizingMaskIntoConstraints = false
        shutterButton.backgroundColor = .white
        shutterButton.layer.cornerRadius = 36
        shutterButton.layer.borderWidth = 5
        shutterButton.layer.borderColor = UIColor.white.withAlphaComponent(0.45).cgColor
        shutterButton.addTarget(self, action: #selector(shutterTapped), for: .touchUpInside)
        bottomBar.contentView.addSubview(shutterButton)
        configureRoundButton(switchButton, image: "arrow.triangle.2.circlepath.camera.fill", action: #selector(switchCamera))
        configureRoundButton(galleryButton, image: "photo.on.rectangle", action: #selector(openGallery))
        bottomBar.contentView.addSubview(switchButton)
        bottomBar.contentView.addSubview(galleryButton)

        zoomStack.translatesAutoresizingMaskIntoConstraints = false
        zoomStack.axis = .horizontal
        zoomStack.spacing = 12
        zoomStack.distribution = .fillEqually
        for (title, tag) in [("0.5×", 5), ("1×", 10)] {
            let button = UIButton(type: .system)
            button.setTitle(title, for: .normal)
            button.setTitleColor(.white, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
            button.backgroundColor = tag == 10 ? UIColor(red: 0.98, green: 0.74, blue: 0.18, alpha: 0.8) : UIColor.black.withAlphaComponent(0.55)
            button.layer.cornerRadius = 18
            button.tag = tag
            button.addTarget(self, action: #selector(zoomPreset(_:)), for: .touchUpInside)
            zoomStack.addArrangedSubview(button)
        }
        view.addSubview(zoomStack)

        countdownLabel.translatesAutoresizingMaskIntoConstraints = false
        countdownLabel.textColor = .white
        countdownLabel.font = .systemFont(ofSize: 78, weight: .thin)
        countdownLabel.textAlignment = .center
        countdownLabel.isHidden = true
        view.addSubview(countdownLabel)
        recordingLabel.translatesAutoresizingMaskIntoConstraints = false
        recordingLabel.textColor = .white
        recordingLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        recordingLabel.backgroundColor = UIColor.systemRed.withAlphaComponent(0.85)
        recordingLabel.layer.cornerRadius = 12
        recordingLabel.clipsToBounds = true
        recordingLabel.textAlignment = .center
        recordingLabel.isHidden = true
        view.addSubview(recordingLabel)
        profileLabel.translatesAutoresizingMaskIntoConstraints = false
        profileLabel.text = PremiumPresetStore.shared.preset(id: settings.premiumPresetID)?.name ?? settings.profile.rawValue
        profileLabel.textColor = UIColor(red: 0.98, green: 0.74, blue: 0.18, alpha: 1)
        profileLabel.font = .systemFont(ofSize: 11, weight: .bold)
        profileLabel.backgroundColor = UIColor.black.withAlphaComponent(0.62)
        profileLabel.layer.cornerRadius = 10; profileLabel.clipsToBounds = true; profileLabel.textAlignment = .center
        view.addSubview(profileLabel)
        videoInfoLabel.translatesAutoresizingMaskIntoConstraints = false
        videoInfoLabel.textColor = .white; videoInfoLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        videoInfoLabel.backgroundColor = UIColor.black.withAlphaComponent(0.62); videoInfoLabel.layer.cornerRadius = 9
        videoInfoLabel.clipsToBounds = true; videoInfoLabel.textAlignment = .center; videoInfoLabel.isHidden = true
        view.addSubview(videoInfoLabel)
        storageLabel.translatesAutoresizingMaskIntoConstraints = false
        storageLabel.textColor = .white; storageLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        storageLabel.backgroundColor = UIColor.black.withAlphaComponent(0.55); storageLabel.layer.cornerRadius = 8
        storageLabel.clipsToBounds = true; storageLabel.textAlignment = .center; storageLabel.isHidden = true
        view.addSubview(storageLabel)
        audioLevelLabel.translatesAutoresizingMaskIntoConstraints = false; audioLevelLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .bold)
        audioLevelLabel.backgroundColor = UIColor.black.withAlphaComponent(0.55); audioLevelLabel.layer.cornerRadius = 8
        audioLevelLabel.clipsToBounds = true; audioLevelLabel.textAlignment = .center; audioLevelLabel.isHidden = true
        view.addSubview(audioLevelLabel)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 14, weight: .medium)
        statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        statusLabel.layer.cornerRadius = 12
        statusLabel.clipsToBounds = true
        statusLabel.textAlignment = .center
        statusLabel.alpha = 0
        view.addSubview(statusLabel)

        focusRing.frame.size = CGSize(width: 72, height: 72)
        focusRing.layer.borderWidth = 2
        focusRing.layer.borderColor = UIColor(red: 0.98, green: 0.74, blue: 0.18, alpha: 1).cgColor
        focusRing.layer.cornerRadius = 36
        focusRing.alpha = 0
        previewView.addSubview(focusRing)
        previewView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(focusTapped(_:))))
        previewView.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(lockFocusAndExposure(_:))))
        previewView.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinchZoom(_:))))

        levelView.translatesAutoresizingMaskIntoConstraints = false
        levelView.backgroundColor = UIColor.white.withAlphaComponent(0.85)
        levelView.layer.cornerRadius = 1.5
        previewView.addSubview(levelView)

        NSLayoutConstraint.activate([
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor), previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewView.topAnchor.constraint(equalTo: view.topAnchor), previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            gridView.leadingAnchor.constraint(equalTo: previewView.leadingAnchor), gridView.trailingAnchor.constraint(equalTo: previewView.trailingAnchor),
            gridView.topAnchor.constraint(equalTo: previewView.topAnchor), gridView.bottomAnchor.constraint(equalTo: previewView.bottomAnchor),
            previewTintView.leadingAnchor.constraint(equalTo: previewView.leadingAnchor), previewTintView.trailingAnchor.constraint(equalTo: previewView.trailingAnchor),
            previewTintView.topAnchor.constraint(equalTo: previewView.topAnchor), previewTintView.bottomAnchor.constraint(equalTo: previewView.bottomAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor), topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.topAnchor.constraint(equalTo: view.topAnchor), topBar.heightAnchor.constraint(equalToConstant: 82),
            topStack.leadingAnchor.constraint(equalTo: topBar.contentView.leadingAnchor, constant: 16),
            topStack.trailingAnchor.constraint(equalTo: topBar.contentView.trailingAnchor, constant: -16),
            topStack.bottomAnchor.constraint(equalTo: topBar.contentView.bottomAnchor, constant: -8), topStack.heightAnchor.constraint(equalToConstant: 42),
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor), bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor), bottomBar.heightAnchor.constraint(equalToConstant: 326),
            presetScroll.leadingAnchor.constraint(equalTo: bottomBar.contentView.leadingAnchor), presetScroll.trailingAnchor.constraint(equalTo: bottomBar.contentView.trailingAnchor),
            presetScroll.topAnchor.constraint(equalTo: bottomBar.contentView.topAnchor, constant: 8), presetScroll.heightAnchor.constraint(equalToConstant: 82),
            presetStack.leadingAnchor.constraint(equalTo: presetScroll.contentLayoutGuide.leadingAnchor, constant: 12), presetStack.trailingAnchor.constraint(equalTo: presetScroll.contentLayoutGuide.trailingAnchor, constant: -12),
            presetStack.topAnchor.constraint(equalTo: presetScroll.contentLayoutGuide.topAnchor), presetStack.bottomAnchor.constraint(equalTo: presetScroll.contentLayoutGuide.bottomAnchor), presetStack.heightAnchor.constraint(equalTo: presetScroll.frameLayoutGuide.heightAnchor),
            modeControl.topAnchor.constraint(equalTo: presetScroll.bottomAnchor, constant: 6), modeControl.centerXAnchor.constraint(equalTo: bottomBar.contentView.centerXAnchor),
            modeControl.widthAnchor.constraint(equalTo: bottomBar.contentView.widthAnchor, constant: -28),
            exposureLabel.leadingAnchor.constraint(equalTo: bottomBar.contentView.leadingAnchor, constant: 24), exposureLabel.topAnchor.constraint(equalTo: modeControl.bottomAnchor, constant: 14), exposureLabel.widthAnchor.constraint(equalToConstant: 52),
            exposureSlider.leadingAnchor.constraint(equalTo: exposureLabel.trailingAnchor, constant: 8), exposureSlider.trailingAnchor.constraint(equalTo: bottomBar.contentView.trailingAnchor, constant: -24), exposureSlider.centerYAnchor.constraint(equalTo: exposureLabel.centerYAnchor),
            shutterButton.centerXAnchor.constraint(equalTo: bottomBar.contentView.centerXAnchor), shutterButton.bottomAnchor.constraint(equalTo: bottomBar.contentView.safeAreaLayoutGuide.bottomAnchor, constant: -20), shutterButton.widthAnchor.constraint(equalToConstant: 72), shutterButton.heightAnchor.constraint(equalToConstant: 72),
            galleryButton.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor), galleryButton.trailingAnchor.constraint(equalTo: shutterButton.leadingAnchor, constant: -54), galleryButton.widthAnchor.constraint(equalToConstant: 54), galleryButton.heightAnchor.constraint(equalToConstant: 54),
            switchButton.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor), switchButton.leadingAnchor.constraint(equalTo: shutterButton.trailingAnchor, constant: 54), switchButton.widthAnchor.constraint(equalToConstant: 54), switchButton.heightAnchor.constraint(equalToConstant: 54),
            zoomStack.centerXAnchor.constraint(equalTo: view.centerXAnchor), zoomStack.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -14), zoomStack.widthAnchor.constraint(equalToConstant: 190), zoomStack.heightAnchor.constraint(equalToConstant: 36),
            countdownLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor), countdownLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            recordingLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor), recordingLabel.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 12), recordingLabel.widthAnchor.constraint(equalToConstant: 112), recordingLabel.heightAnchor.constraint(equalToConstant: 28),
            profileLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14), profileLabel.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 12), profileLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 100), profileLabel.heightAnchor.constraint(equalToConstant: 24),
            videoInfoLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor), videoInfoLabel.topAnchor.constraint(equalTo: recordingLabel.bottomAnchor, constant: 8), videoInfoLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 210), videoInfoLabel.heightAnchor.constraint(equalToConstant: 24),
            storageLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor), storageLabel.topAnchor.constraint(equalTo: videoInfoLabel.bottomAnchor, constant: 6), storageLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 170), storageLabel.heightAnchor.constraint(equalToConstant: 22),
            audioLevelLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor), audioLevelLabel.topAnchor.constraint(equalTo: storageLabel.bottomAnchor, constant: 6), audioLevelLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 150), audioLevelLabel.heightAnchor.constraint(equalToConstant: 20),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor), statusLabel.bottomAnchor.constraint(equalTo: zoomStack.topAnchor, constant: -16), statusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 170), statusLabel.heightAnchor.constraint(equalToConstant: 34)
            ,levelView.centerXAnchor.constraint(equalTo: previewView.centerXAnchor), levelView.centerYAnchor.constraint(equalTo: previewView.centerYAnchor), levelView.widthAnchor.constraint(equalToConstant: 64), levelView.heightAnchor.constraint(equalToConstant: 3)
        ])
        applyPremiumPreview()
    }

    private func configureTopButton(_ button: UIButton, image: String, action: Selector) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: image), for: .normal)
        button.tintColor = .white
        button.addTarget(self, action: action, for: .touchUpInside)
        button.widthAnchor.constraint(equalToConstant: 42).isActive = true
    }

    private func rebuildPresetCarousel() {
        presetStack.arrangedSubviews.forEach { presetStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        presetButtons.removeAll()
        let selected = settings.premiumPresetID
        for preset in PremiumPresetStore.shared.all {
            let column = UIStackView(); column.axis = .vertical; column.alignment = .center; column.spacing = 3
            column.translatesAutoresizingMaskIntoConstraints = false; column.widthAnchor.constraint(equalToConstant: 70).isActive = true
            let button = UIButton(type: .system)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 52).isActive = true; button.heightAnchor.constraint(equalToConstant: 52).isActive = true
            button.layer.cornerRadius = 26; button.clipsToBounds = false
            button.setTitle(preset.shortName, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: preset.shortName.count > 4 ? 8 : 11, weight: .heavy)
            button.setTitleColor(.white, for: .normal)
            button.backgroundColor = thumbnailColor(for: preset.id)
            button.layer.borderWidth = preset.id == selected ? 3 : 1
            button.layer.borderColor = (preset.id == selected ? UIColor.systemYellow : UIColor.white.withAlphaComponent(0.32)).cgColor
            button.accessibilityIdentifier = preset.id
            button.accessibilityLabel = preset.name
            button.addTarget(self, action: #selector(premiumPresetTapped(_:)), for: .touchUpInside)
            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(premiumPresetLongPressed(_:))); button.addGestureRecognizer(longPress)
            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(premiumPresetDoubleTapped(_:))); doubleTap.numberOfTapsRequired = 2; button.addGestureRecognizer(doubleTap)
            let label = UILabel(); label.text = preset.id == PremiumPresetID.off.rawValue ? "БЕЗ" : preset.shortName
            label.font = .systemFont(ofSize: 8, weight: .semibold); label.textColor = .white; label.textAlignment = .center
            label.adjustsFontSizeToFitWidth = true; label.minimumScaleFactor = 0.6
            column.addArrangedSubview(button); column.addArrangedSubview(label); presetStack.addArrangedSubview(column)
            presetButtons[preset.id] = button
        }
    }

    private func thumbnailColor(for id: String) -> UIColor {
        switch PremiumPresetID(rawValue: id) {
        case .off: return UIColor(white: 0.20, alpha: 1)
        case .fullFramePro: return UIColor(red: 0.16, green: 0.23, blue: 0.30, alpha: 1)
        case .forestSignature: return UIColor(red: 0.08, green: 0.28, blue: 0.18, alpha: 1)
        case .goldenHourElite: return UIColor(red: 0.72, green: 0.36, blue: 0.08, alpha: 1)
        case .leicaInspired: return UIColor(red: 0.34, green: 0.12, blue: 0.10, alpha: 1)
        case .sonyDetailPro: return UIColor(red: 0.05, green: 0.24, blue: 0.46, alpha: 1)
        case .canonPortraitPro: return UIColor(red: 0.58, green: 0.25, blue: 0.20, alpha: 1)
        case .cinemaNight: return UIColor(red: 0.04, green: 0.06, blue: 0.15, alpha: 1)
        case .cinematicTealSoft: return UIColor(red: 0.02, green: 0.28, blue: 0.30, alpha: 1)
        case .cleanInstagramPro: return UIColor(red: 0.46, green: 0.18, blue: 0.48, alpha: 1)
        case .none: return UIColor(white: 0.18, alpha: 1)
        }
    }

    @objc private func premiumPresetTapped(_ sender: UIButton) {
        guard let id = sender.accessibilityIdentifier, let preset = PremiumPresetStore.shared.preset(id: id) else { return }
        settings.premiumPresetID = id
        settings.presetIntensity = PremiumPresetStore.shared.intensity
        PremiumPresetStore.shared.select(id)
        settings.save(lens: currentLensKey)
        profileLabel.text = preset.name
        if id != PremiumPresetID.off.rawValue {
            exposureSlider.value = preset.parameters.exposure.clamped(-2, 2)
            exposureChanged()
        }
        updatePresetSelection(); applyPremiumPreview()
        showStatus("\(preset.name) • \(Int(settings.presetIntensity * 100))%")
    }

    @objc private func premiumPresetDoubleTapped(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended, let button = gesture.view as? UIButton else { return }
        premiumPresetTapped(button)
        PremiumPresetStore.shared.intensity = 1; settings.presetIntensity = 1; settings.save(lens: currentLensKey)
        applyPremiumPreview(); showStatus("Интенсивность 100%")
    }

    @objc private func premiumPresetLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let button = gesture.view as? UIButton else { return }
        premiumPresetTapped(button)
        let alert = UIAlertController(title: "Интенсивность пресета", message: "\n\n\(Int(settings.presetIntensity * 100))%", preferredStyle: .alert)
        let slider = UISlider(frame: CGRect(x: 22, y: 72, width: 226, height: 32))
        slider.minimumValue = 0; slider.maximumValue = 1; slider.value = settings.presetIntensity
        slider.minimumTrackTintColor = UIColor(red: 0.98, green: 0.74, blue: 0.18, alpha: 1)
        slider.addTarget(self, action: #selector(presetIntensityChanged(_:)), for: .valueChanged)
        alert.view.addSubview(slider)
        alert.addAction(UIAlertAction(title: "Готово", style: .default))
        present(alert, animated: true)
    }

    @objc private func presetIntensityChanged(_ slider: UISlider) {
        settings.presetIntensity = slider.value.clamped(0, 1)
        PremiumPresetStore.shared.intensity = settings.presetIntensity
        settings.save(lens: currentLensKey); applyPremiumPreview()
        if let alert = presentedViewController as? UIAlertController { alert.message = "\n\n\(Int(settings.presetIntensity * 100))%" }
    }

    private func updatePresetSelection() {
        for (id, button) in presetButtons {
            button.layer.borderWidth = id == settings.premiumPresetID ? 3 : 1
            button.layer.borderColor = (id == settings.premiumPresetID ? UIColor.systemYellow : UIColor.white.withAlphaComponent(0.32)).cgColor
        }
    }

    private func applyPremiumPreview() {
        let id = PremiumPresetID(rawValue: settings.premiumPresetID)
        let strength = CGFloat(settings.presetIntensity.clamped(0, 1))
        switch id {
        case .forestSignature: previewTintView.backgroundColor = UIColor(red: 0.10, green: 0.26, blue: 0.10, alpha: 0.09 * strength)
        case .goldenHourElite: previewTintView.backgroundColor = UIColor(red: 1.0, green: 0.48, blue: 0.10, alpha: 0.10 * strength)
        case .leicaInspired: previewTintView.backgroundColor = UIColor(red: 0.42, green: 0.16, blue: 0.10, alpha: 0.055 * strength)
        case .canonPortraitPro: previewTintView.backgroundColor = UIColor(red: 1.0, green: 0.42, blue: 0.30, alpha: 0.045 * strength)
        case .cinemaNight: previewTintView.backgroundColor = UIColor(red: 0.05, green: 0.08, blue: 0.22, alpha: 0.10 * strength)
        case .cinematicTealSoft: previewTintView.backgroundColor = UIColor(red: 0.0, green: 0.24, blue: 0.27, alpha: 0.08 * strength)
        case .cleanInstagramPro: previewTintView.backgroundColor = UIColor.white.withAlphaComponent(0.025 * strength)
        default: previewTintView.backgroundColor = .clear
        }
        let vignette = PremiumPresetStore.shared.preset(id: settings.premiumPresetID)?.parameters.vignette ?? 0
        previewVignette.isHidden = vignette == 0 || strength == 0
        previewVignette.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(min(0.30, abs(CGFloat(vignette)) * strength * 1.5)).cgColor]
    }

    private func configureRoundButton(_ button: UIButton, image: String, action: Selector) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: image), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        button.layer.cornerRadius = 27
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func startMotionMonitoring() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 0.12
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let rotation = motion?.rotationRate else { return }
            let movement = abs(rotation.x) + abs(rotation.y) + abs(rotation.z)
            self?.isDeviceStable = movement < 0.42
            if let gravity = motion?.gravity {
                let angle = atan2(gravity.x, gravity.y) - .pi
                self?.levelView.transform = CGAffineTransform(rotationAngle: CGFloat(angle))
                self?.levelView.backgroundColor = abs(gravity.x) < 0.025 ? UIColor.systemGreen : UIColor.white.withAlphaComponent(0.85)
            }
        }
    }

    @objc private func thermalStateChanged() {
        lastThermalState = ProcessInfo.processInfo.thermalState
        switch lastThermalState {
        case .serious:
            showStatus("Нагрев: обработка снижена")
        case .critical:
            showStatus("Критический нагрев")
            if movieOutput.isRecording { stopRecording() }
        default: break
        }
    }

    @objc private func appWillResignActive() {
        if movieOutput.isRecording { stopRecording(); showStatus("Запись завершена при сворачивании") }
    }

    private func freeDiskBytes() -> Int64 {
        let values = try? FileManager.default.temporaryDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    private func estimatedBytesPerMinute() -> Int64 {
        Int64(videoSettings.bitrateMbps * 1_000_000 / 8 * 60) + Int64(videoSettings.audioBitrateKbps * 1_000 / 8 * 60)
    }

    private func storageDescription() -> String {
        let free = max(0, freeDiskBytes() - 500_000_000)
        let perMinute = max(1, estimatedBytesPerMinute())
        return String(format: "Свободно %.1f ГБ • ≈ %d мин", Double(freeDiskBytes()) / 1_000_000_000, Int(free / perMinute))
    }

    private func requestCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                DispatchQueue.main.async { allowed ? self?.configureSession() : self?.showPermissionMessage() }
            }
        default: showPermissionMessage()
        }
    }

    private func showPermissionMessage() {
        let alert = UIAlertController(title: "Нужен доступ к камере", message: "Разрешите доступ к камере в настройках iPhone.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Настройки", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        })
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        present(alert, animated: true)
    }

    private func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self, !self.isConfigured else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            do {
                guard let device = self.cameraDevice(position: .back, lens: .builtInWideAngleCamera) else { throw CameraError.noCamera }
                let input = try AVCaptureDeviceInput(device: device)
                guard self.session.canAddInput(input) else { throw CameraError.inputUnavailable }
                self.session.addInput(input)
                self.videoInput = input
                guard self.session.canAddOutput(self.photoOutput), self.session.canAddOutput(self.movieOutput) else { throw CameraError.outputUnavailable }
                self.session.addOutput(self.photoOutput)
                self.session.addOutput(self.movieOutput)
                self.photoOutput.isHighResolutionCaptureEnabled = true
                self.photoOutput.maxPhotoQualityPrioritization = .quality
                if self.photoOutput.isDepthDataDeliverySupported { self.photoOutput.isDepthDataDeliveryEnabled = true }
                self.settings.rawEnabled = false
                self.movieOutput.movieFragmentInterval = CMTime(seconds: 1, preferredTimescale: 600)
                self.availableVideoModes = VideoModeDiscovery.modes(for: device)
                self.isConfigured = true
                self.session.commitConfiguration()
                self.applyManualControls()
                self.session.startRunning()
                DispatchQueue.main.async { self.showDeviceCapabilities() }
            } catch {
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.showStatus("Камера недоступна") }
            }
        }
    }

    private func startSessionIfPossible() {
        sessionQueue.async { [weak self] in guard let self, self.isConfigured, !self.session.isRunning else { return }; self.session.startRunning() }
    }

    private func cameraDevice(position: AVCaptureDevice.Position, lens: AVCaptureDevice.DeviceType) -> AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(deviceTypes: [lens], mediaType: .video, position: position).devices.first
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    private func replaceVideoInput(position: AVCaptureDevice.Position, lens: AVCaptureDevice.DeviceType) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.cameraDevice(position: position, lens: lens) else { return }
            do {
                let newInput = try AVCaptureDeviceInput(device: device)
                self.session.beginConfiguration()
                let oldInput = self.videoInput
                if let oldInput { self.session.removeInput(oldInput) }
                if self.session.canAddInput(newInput) { self.session.addInput(newInput); self.videoInput = newInput; self.availableVideoModes = VideoModeDiscovery.modes(for: device) }
                else if let oldInput, self.session.canAddInput(oldInput) { self.session.addInput(oldInput) }
                self.session.commitConfiguration()
                self.applyManualControls()
                if self.isVideoMode { self.applyVideoConfiguration(showFallback: true) }
            } catch { DispatchQueue.main.async { self.showStatus("Объектив недоступен") } }
        }
    }

    private func applyManualControls() {
        guard let device = videoInput?.device else { return }
        do {
            try device.lockForConfiguration()
            if settings.manualEnabled {
                let seconds = min(max(Double(settings.shutterSeconds), CMTimeGetSeconds(device.activeFormat.minExposureDuration)), CMTimeGetSeconds(device.activeFormat.maxExposureDuration))
                let iso = min(max(settings.iso, device.activeFormat.minISO), device.activeFormat.maxISO)
                device.setExposureModeCustom(duration: CMTimeMakeWithSeconds(seconds, preferredTimescale: 1_000_000_000), iso: iso)
                if device.isLockingFocusWithCustomLensPositionSupported { device.setFocusModeLocked(lensPosition: min(max(settings.focus, 0), 1)) }
                if device.isLockingWhiteBalanceWithCustomDeviceGainsSupported {
                    var gains = device.deviceWhiteBalanceGains(for: .init(temperature: settings.whiteBalance, tint: 0))
                    gains.redGain = min(max(gains.redGain, 1), device.maxWhiteBalanceGain)
                    gains.greenGain = min(max(gains.greenGain, 1), device.maxWhiteBalanceGain)
                    gains.blueGain = min(max(gains.blueGain, 1), device.maxWhiteBalanceGain)
                    device.setWhiteBalanceModeLocked(with: gains)
                }
            } else {
                if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
                if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
                if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { device.whiteBalanceMode = .continuousAutoWhiteBalance }
            }
            device.unlockForConfiguration()
        } catch { }
    }

    private func applyVideoConfiguration(showFallback: Bool) {
        guard let device = videoInput?.device else { return }
        var requested = videoSettings.validated()
        guard let selected = VideoModeDiscovery.closest(to: requested, in: availableVideoModes) else {
            DispatchQueue.main.async { self.showStatus("Нет совместимого видеорежима") }
            return
        }
        let wasFallback = selected.resolution != requested.resolution || selected.fps != requested.fps
        requested.resolution = selected.resolution; requested.fps = selected.fps

        session.beginConfiguration()
        if session.canSetSessionPreset(.inputPriority) { session.sessionPreset = .inputPriority }
        do {
            try device.lockForConfiguration()
            device.activeFormat = selected.format
            let duration = CMTime(value: 1, timescale: CMTimeScale(selected.fps))
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            let hdrAllowed = requested.codec == .hevc && selected.format.isVideoHDRSupported
            requested.hdrEnabled = requested.hdrEnabled && hdrAllowed
            device.automaticallyAdjustsVideoHDREnabled = false
            device.isVideoHDREnabled = requested.hdrEnabled && hdrAllowed

            var profileEV = requested.exposure
            var profileTemperature = requested.temperature
            switch requested.profile {
            case .natural: break
            case .forestGolden: profileEV -= 0.08; profileTemperature = 6000
            case .cinematic: profileEV -= 0.12; profileTemperature = 5700
            case .hdrNatural: profileEV -= 0.10
            case .lowLight: profileEV -= 0.18; profileTemperature = 5000
            }
            if requested.manualEnabled {
                let minimum = CMTimeGetSeconds(selected.format.minExposureDuration), maximum = CMTimeGetSeconds(selected.format.maxExposureDuration)
                let duration = min(max(Double(requested.shutterSeconds), minimum), min(maximum, 1.0 / Double(max(1, selected.fps))))
                let iso = min(max(requested.iso, selected.format.minISO), selected.format.maxISO)
                device.setExposureModeCustom(duration: CMTimeMakeWithSeconds(duration, preferredTimescale: 1_000_000_000), iso: iso)
            } else {
                if device.isExposureModeSupported(requested.exposureLock ? .locked : .continuousAutoExposure) { device.exposureMode = requested.exposureLock ? .locked : .continuousAutoExposure }
                device.setExposureTargetBias(min(max(profileEV, device.minExposureTargetBias), device.maxExposureTargetBias))
            }
            if requested.manualEnabled && device.isLockingFocusWithCustomLensPositionSupported { device.setFocusModeLocked(lensPosition: requested.focus) }
            else if requested.focusLock, device.isFocusModeSupported(.locked) { device.focusMode = .locked }
            else if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if requested.whiteBalanceLock && device.isLockingWhiteBalanceWithCustomDeviceGainsSupported {
                var gains = device.deviceWhiteBalanceGains(for: .init(temperature: profileTemperature, tint: requested.tint))
                gains.redGain = min(max(gains.redGain, 1), device.maxWhiteBalanceGain)
                gains.greenGain = min(max(gains.greenGain, 1), device.maxWhiteBalanceGain)
                gains.blueGain = min(max(gains.blueGain, 1), device.maxWhiteBalanceGain)
                device.setWhiteBalanceModeLocked(with: gains)
            } else if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { device.whiteBalanceMode = .continuousAutoWhiteBalance }
            device.unlockForConfiguration()
        } catch {
            session.commitConfiguration()
            DispatchQueue.main.async { self.showStatus("Не удалось применить VIDEO PRO") }
            return
        }

        if let connection = movieOutput.connection(with: .video) {
            connection.videoOrientation = .portrait
            connection.isVideoMirrored = device.position == .front
            let wantedStabilization: AVCaptureVideoStabilizationMode
            switch requested.stabilization {
            case .off: wantedStabilization = .off
            case .standard: wantedStabilization = .standard
            case .cinematic: wantedStabilization = .cinematic
            case .auto: wantedStabilization = connection.isVideoStabilizationSupported ? .cinematic : .off
            }
            connection.preferredVideoStabilizationMode = connection.isVideoStabilizationSupported ? wantedStabilization : .off

            let availableCodecs = movieOutput.availableVideoCodecTypes
            let preferred: AVVideoCodecType = requested.codec == .hevc ? .hevc : .h264
            let actualCodec: AVVideoCodecType = availableCodecs.contains(preferred) ? preferred : .h264
            if actualCodec != preferred { requested.codec = .h264 }
            let videoOutputSettings: [String: Any] = [
                AVVideoCodecKey: actualCodec,
                AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: Int(requested.bitrateMbps * 1_000_000)]
            ]
            movieOutput.setOutputSettings(videoOutputSettings, for: connection)
        }
        if let audioConnection = movieOutput.connection(with: .audio) {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: requested.audioSampleRate,
                AVEncoderBitRateKey: requested.audioBitrateKbps * 1_000,
                AVNumberOfChannelsKey: 2
            ]
            movieOutput.setOutputSettings(audioSettings, for: audioConnection)
        }
        session.commitConfiguration()
        videoSettings = requested; videoSettings.save()
        DispatchQueue.main.async {
            let hdrText = device.isVideoHDREnabled ? "HDR" : "SDR"
            self.videoInfoLabel.text = "  \(selected.title) • \(requested.codec.rawValue.uppercased()) • \(hdrText) • \(self.currentLensKey)  "
            self.storageLabel.text = "  \(self.storageDescription())  "
            if showFallback && wasFallback { self.showStatus("Выбран ближайший режим: \(selected.title)") }
        }
    }

    @objc private func toggleFlash() {
        flashMode = flashMode == .off ? .on : (flashMode == .on ? .auto : .off)
        let symbol = flashMode == .on ? "bolt.fill" : (flashMode == .auto ? "bolt.badge.a.fill" : "bolt.slash.fill")
        flashButton.setImage(UIImage(systemName: symbol), for: .normal)
        if isVideoMode { applyTorchMode() }
    }

    private func applyTorchMode() {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoInput?.device, device.hasTorch else { return }
            do {
                try device.lockForConfiguration()
                switch self.flashMode {
                case .off: device.torchMode = .off
                case .on: try device.setTorchModeOn(level: min(0.65, AVCaptureDevice.maxAvailableTorchLevel))
                case .auto:
                    if device.iso > min(device.activeFormat.maxISO * 0.28, 500) { try device.setTorchModeOn(level: min(0.42, AVCaptureDevice.maxAvailableTorchLevel)) }
                    else { device.torchMode = .off }
                @unknown default: device.torchMode = .off
                }
                device.unlockForConfiguration()
            } catch { }
        }
    }

    @objc private func toggleTimer() {
        timerSeconds = timerSeconds == 0 ? 3 : (timerSeconds == 3 ? 10 : 0)
        timerButton.setTitle(timerSeconds == 0 ? nil : "\(timerSeconds)", for: .normal)
        timerButton.setImage(timerSeconds == 0 ? UIImage(systemName: "timer") : nil, for: .normal)
        showStatus(timerSeconds == 0 ? "Таймер выключен" : "Таймер \(timerSeconds) с")
    }

    @objc private func toggleGrid() {
        gridVisible.toggle(); gridView.isHidden = !gridVisible
        gridButton.tintColor = gridVisible ? UIColor(red: 0.98, green: 0.74, blue: 0.18, alpha: 1) : .white
    }

    @objc private func toggleVideoMode() {
        guard !movieOutput.isRecording else { stopRecording(); return }
        isVideoMode.toggle()
        videoButton.tintColor = isVideoMode ? .systemRed : .white
        modeControl.isEnabled = !isVideoMode
        modeControl.alpha = isVideoMode ? 0.4 : 1
        shutterButton.backgroundColor = isVideoMode ? .systemRed : .white
        videoInfoLabel.isHidden = !isVideoMode
        storageLabel.isHidden = !isVideoMode
        profileLabel.text = isVideoMode ? videoSettings.profile.rawValue : (PremiumPresetStore.shared.preset(id: settings.premiumPresetID)?.name ?? settings.profile.rawValue)
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.isVideoMode { self.applyVideoConfiguration(showFallback: true) }
            else {
                self.session.beginConfiguration(); if self.session.canSetSessionPreset(.photo) { self.session.sessionPreset = .photo }; self.session.commitConfiguration()
                self.applyManualControls(); self.flashMode = .off; self.applyTorchMode()
            }
        }
        showStatus(isVideoMode ? "VIDEO PRO • \(videoSettings.profile.rawValue)" : photoMode.title)
    }

    @objc private func modeChanged() {
        photoMode = PhotoMode(rawValue: modeControl.selectedSegmentIndex) ?? .normal
        isVideoMode = false; videoButton.tintColor = .white; shutterButton.backgroundColor = .white
        videoInfoLabel.isHidden = true; storageLabel.isHidden = true; profileLabel.text = PremiumPresetStore.shared.preset(id: settings.premiumPresetID)?.name ?? settings.profile.rawValue
        showStatus(photoMode.title)
    }

    @objc private func exposureChanged() {
        let value = exposureSlider.value
        exposureLabel.text = String(format: "EV %.1f", value)
        if isVideoMode { videoSettings.exposure = min(max(value, -1), 1); videoSettings.save() }
        guard !settings.manualEnabled else { return }
        sessionQueue.async { [weak self] in
            guard let device = self?.videoInput?.device else { return }
            do { try device.lockForConfiguration(); device.setExposureTargetBias(min(max(value, device.minExposureTargetBias), device.maxExposureTargetBias)); device.unlockForConfiguration() } catch { }
        }
    }

    @objc private func shutterTapped() {
        if isVideoMode { movieOutput.isRecording ? stopRecording() : prepareVideoRecording() }
        else { beginCountdown(seconds: timerSeconds) { [weak self] in self?.captureSeries() } }
    }

    private func beginCountdown(seconds: Int, completion: @escaping () -> Void) {
        guard seconds > 0 else { completion(); return }
        var remaining = seconds
        countdownLabel.text = "\(remaining)"; countdownLabel.isHidden = false; shutterButton.isEnabled = false
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            remaining -= 1
            if remaining <= 0 { timer.invalidate(); self?.countdownLabel.isHidden = true; self?.shutterButton.isEnabled = true; completion() }
            else { self?.countdownLabel.text = "\(remaining)" }
        }
    }

    private func exposureBrackets() -> [Float] {
        let device = videoInput?.device
        let lowLight = photoMode == .night || (settings.autoScene && ((device?.iso ?? 0) > 520 || CMTimeGetSeconds(device?.exposureDuration ?? .zero) > 1.0 / 24.0))
        var count = settings.frameCount
        if settings.fastCapture { count = 1 }
        if lowLight { count = min(16, max(10, count)) }
        else if (device?.iso ?? 0) < 160 { count = min(10, max(6, count)) }
        else { count = min(12, max(8, count)) }
        if !isDeviceStable { count = min(count, lowLight ? 6 : 4) }
        if flashMode == .on { count = min(count, 3) }
        if videoInput?.device.position == .front { count = min(count, 6) }
        if lastThermalState == .serious || lastThermalState == .critical { count = min(count, 4) }
        guard count > 1 else { return [exposureSlider.value] }
        let range: Float = flashMode == .on ? 0.35 : (lowLight ? 0.85 : (photoMode == .hdr || settings.profile == .hdrNatural ? 1.10 : 0.52 + settings.hdrStrength * 0.30))
        let step = (range * 2.0) / Float(count - 1)
        let flashCompensation: Float = flashMode == .on ? -0.50 : 0
        let base = exposureSlider.value + flashCompensation - range
        var values: [Float] = []
        for index in 0..<count { values.append(base + step * Float(index)) }
        return values
    }

    private func captureSeries() {
        guard !isCapturingSeries else { return }
        isCapturingSeries = true; shutterButton.isEnabled = false
        let brackets = exposureBrackets()
        if brackets.count > 4 && !isDeviceStable { showStatus("Держите iPhone неподвижно • \(brackets.count) кадров") }
        captureNext(brackets: brackets, index: 0, accumulator: SeriesAccumulator())
    }

    private func captureNext(brackets: [Float], index: Int, accumulator: SeriesAccumulator) {
        if index >= brackets.count { processCapturedFrames(accumulator.frames); return }
        showStatus("\(photoMode.title): кадр \(index + 1)/\(brackets.count)")
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoInput?.device else { return }
            if !self.settings.manualEnabled {
                do { try device.lockForConfiguration(); device.setExposureTargetBias(min(max(brackets[index], device.minExposureTargetBias), device.maxExposureTargetBias)); device.unlockForConfiguration() } catch { }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + (index == 0 ? 0.08 : 0.16)) { [weak self] in
                self?.captureOneFrame(wantsRaw: index == 0 && self?.photoMode == .normal) { frame in
                    guard let self else { return }
                    if let frame { accumulator.frames.append(frame) }
                    self.captureNext(brackets: brackets, index: index + 1, accumulator: accumulator)
                }
            }
        }
    }

    private func captureOneFrame(wantsRaw: Bool, completion: @escaping (CapturedFrame?) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let rawAvailable = false
            let captureSettings: AVCapturePhotoSettings
            if rawAvailable {
                captureSettings = AVCapturePhotoSettings(rawPixelFormatType: self.photoOutput.availableRawPhotoPixelFormatTypes[0], processedFormat: [AVVideoCodecKey: AVVideoCodecType.hevc])
            } else {
                captureSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            }
            captureSettings.isHighResolutionPhotoEnabled = true
            captureSettings.photoQualityPrioritization = self.settings.fastCapture ? .balanced : .quality
            if self.videoInput?.device.hasFlash == true { captureSettings.flashMode = self.flashMode }
            if self.photoMode == .portrait && self.photoOutput.isDepthDataDeliverySupported { captureSettings.isDepthDataDeliveryEnabled = true }
            if let connection = self.photoOutput.connection(with: .video) {
                connection.videoOrientation = .portrait
                connection.isVideoMirrored = self.videoInput?.device.position == .front && self.settings.mirrorFront
            }
            let id = UUID()
            let delegate = FrameCaptureDelegate { [weak self] frame in
                self?.activeDelegates.removeValue(forKey: id)
                completion(frame)
            }
            self.activeDelegates[id] = delegate
            self.photoOutput.capturePhoto(with: captureSettings, delegate: delegate)
        }
    }

    private func processCapturedFrames(_ frames: [CapturedFrame]) {
        guard !frames.isEmpty else { finishCapture(message: "Ошибка съёмки"); return }
        showStatus("Обработка…")
        let mode = photoMode, prefs = settings
        let deviceISO = videoInput?.device.iso ?? 100
        let stable = isDeviceStable
        let usedFlash = frames.contains(where: \.flashFired)
        processingQueue.async { [weak self] in
            let analysis = PhotoSceneAnalyzer.analyze(frames.first?.image)
            let context = PhotoProcessingContext(scene: analysis.scene, brightness: analysis.brightness, dynamicRange: analysis.dynamicRange, iso: deviceISO, flash: usedFlash, stable: stable, lens: self?.currentLensKey ?? "1x", frontCamera: self.map { $0.videoInput?.device.position == .front } ?? false)
            let result = PhotoProcessor.process(frames.map(\.image), mode: mode, settings: prefs, context: context)
            DispatchQueue.main.async {
                guard let self else { return }
                guard let image = result else { self.finishCapture(message: "Ошибка обработки"); return }
                let metadata = frames.first?.metadata ?? [:]
                let data = prefs.savePNG ? ImageEncoder.png(image, metadata: metadata) : ImageEncoder.jpeg(image, metadata: metadata, quality: 0.96)
                guard let data else { self.finishCapture(message: "Ошибка кодирования фото"); return }
                self.galleryButton.setImage(image.withRenderingMode(.alwaysOriginal), for: .normal)
                self.galleryButton.imageView?.contentMode = .scaleAspectFill; self.galleryButton.clipsToBounds = true
                self.saveCapture(processed: prefs.saveProcessed ? data : nil, original: prefs.saveOriginal ? frames.first?.originalData : nil, raw: nil)
                self.finishCapture(message: "Фото сохранено в \(prefs.savePNG ? "PNG" : "JPEG") • \(analysis.scene.rawValue)")
            }
        }
    }

    private func finishCapture(message: String) {
        isCapturingSeries = false; shutterButton.isEnabled = true; showStatus(message)
        if !settings.manualEnabled { exposureChanged() }
    }

    private func prepareVideoRecording() {
        guard lastThermalState != .critical else { showStatus("Запись недоступна: критический нагрев"); return }
        let required = max(600_000_000, estimatedBytesPerMinute() * 3)
        guard freeDiskBytes() > required else { showStatus("Недостаточно места для безопасной записи"); return }
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .notDetermined { AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in DispatchQueue.main.async { self?.startRecording() } } }
        else { startRecording() }
    }

    private func startRecording() {
        sessionQueue.async { [weak self] in
            guard let self, !self.movieOutput.isRecording else { return }
            self.addAudioInputIfAllowed()
            self.configureAudioSession()
            self.applyVideoConfiguration(showFallback: true)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("TigrCamera-\(UUID().uuidString).mov")
            if let connection = self.movieOutput.connection(with: .video) { connection.videoOrientation = .portrait; connection.isVideoMirrored = self.videoInput?.device.position == .front }
            self.movieOutput.maxRecordedFileSize = max(100_000_000, self.freeDiskBytes() - 500_000_000)
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
            DispatchQueue.main.async { self.setRecordingUI(active: true) }
        }
    }

    private func addAudioInputIfAllowed() {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized, audioInput == nil, let device = AVCaptureDevice.default(for: .audio), let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        if session.canAddInput(input) { session.addInput(input); audioInput = input }
        if session.canAddOutput(audioMeterOutput) {
            session.addOutput(audioMeterOutput)
            audioMeterOutput.setSampleBufferDelegate(audioLevelMonitor, queue: DispatchQueue(label: "com.tigr.camera.audio-meter", qos: .userInteractive))
        }
        session.commitConfiguration()
    }

    private func configureAudioSession() {
        let audio = AVAudioSession.sharedInstance()
        do {
            try audio.setCategory(.playAndRecord, mode: .videoRecording, options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker])
            try audio.setPreferredSampleRate(48_000)
            try audio.setActive(true)
        } catch { DispatchQueue.main.async { self.showStatus("Аудиовход работает в системном режиме") } }
    }

    private func stopRecording() {
        sessionQueue.async { [weak self] in
            guard let self else { return }; self.movieOutput.stopRecording()
            if let device = self.videoInput?.device, device.hasTorch { try? device.lockForConfiguration(); device.torchMode = .off; device.unlockForConfiguration() }
        }
        setRecordingUI(active: false)
    }

    private func setRecordingUI(active: Bool) {
        recordingTimer?.invalidate(); recordingStartedAt = active ? Date() : nil; recordingLabel.isHidden = !active
        videoInfoLabel.isHidden = !isVideoMode; storageLabel.isHidden = !isVideoMode
        audioLevelLabel.isHidden = !active
        galleryButton.setImage(UIImage(systemName: active ? "camera.fill" : "photo.on.rectangle"), for: .normal)
        shutterButton.layer.cornerRadius = active ? 12 : 36; shutterButton.transform = active ? CGAffineTransform(scaleX: 0.62, y: 0.62) : .identity
        if active { recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, let start = self.recordingStartedAt else { return }; let seconds = Int(Date().timeIntervalSince(start)); self.recordingLabel.text = String(format: " REC %02d:%02d ", seconds / 60, seconds % 60)
            if seconds % 4 == 0 { self.storageLabel.text = "  \(self.storageDescription())  " }
            if self.freeDiskBytes() < 550_000_000 { self.showStatus("Мало места — запись завершается"); self.stopRecording() }
            if ProcessInfo.processInfo.thermalState == .critical { self.showStatus("Перегрев — запись завершена безопасно"); self.stopRecording() }
        }}
    }

    @objc private func switchCamera() {
        guard !movieOutput.isRecording, !isCapturingSeries else { showStatus("Смена камеры во время записи недоступна"); return }
        settings.save(lens: currentLensKey)
        let goingFront = videoInput?.device.position == .back
        currentLensKey = goingFront ? "front" : "1x"
        settings = ProcessingSettings.load(lens: currentLensKey)
        replaceVideoInput(position: goingFront ? .front : .back, lens: .builtInWideAngleCamera)
        updatePresetSelection(); applyPremiumPreview()
    }

    @objc private func zoomPreset(_ sender: UIButton) {
        guard !isCapturingSeries else { return }
        if videoInput?.device.position == .front { applyZoom(1); return }
        settings.save(lens: currentLensKey)
        currentLensKey = sender.tag == 5 ? "0.5x" : "1x"
        settings = ProcessingSettings.load(lens: currentLensKey)
        let lens: AVCaptureDevice.DeviceType = sender.tag == 5 ? .builtInUltraWideCamera : .builtInWideAngleCamera
        replaceVideoInput(position: .back, lens: lens)
        updatePresetSelection(); applyPremiumPreview()
        if sender.tag == 5, (videoInput?.device.iso ?? 0) > 420 { showStatus("Для лучшего качества переключитесь на 1×") }
        zoomStack.arrangedSubviews.compactMap { $0 as? UIButton }.forEach { $0.backgroundColor = $0 == sender ? UIColor(red: 0.98, green: 0.74, blue: 0.18, alpha: 0.8) : UIColor.black.withAlphaComponent(0.55) }
    }

    @objc private func pinchZoom(_ gesture: UIPinchGestureRecognizer) {
        guard let device = videoInput?.device, gesture.state == .changed else { return }; applyZoom(device.videoZoomFactor * gesture.scale); gesture.scale = 1
    }

    private func applyZoom(_ factor: CGFloat) {
        sessionQueue.async { [weak self] in guard let self, let device = self.videoInput?.device else { return }; do { try device.lockForConfiguration(); let target = min(max(factor, 1), min(device.activeFormat.videoMaxZoomFactor, 8)); if self.movieOutput.isRecording { device.ramp(toVideoZoomFactor: target, withRate: 2.0) } else { device.videoZoomFactor = target }; device.unlockForConfiguration() } catch { } }
    }

    @objc private func focusTapped(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: previewView), devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)
        focusRing.center = point; focusRing.transform = CGAffineTransform(scaleX: 1.35, y: 1.35); focusRing.alpha = 1
        UIView.animate(withDuration: 0.25, animations: { self.focusRing.transform = .identity }) { _ in UIView.animate(withDuration: 0.35, delay: 0.45, animations: { self.focusRing.alpha = 0 }) }
        guard !settings.manualEnabled else { return }
        sessionQueue.async { [weak self] in guard let device = self?.videoInput?.device else { return }; do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = devicePoint; device.focusMode = .autoFocus }
            if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = devicePoint; device.exposureMode = .continuousAutoExposure }
            device.unlockForConfiguration()
        } catch { } }
    }

    @objc private func lockFocusAndExposure(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, !settings.manualEnabled else { return }
        let point = gesture.location(in: previewView), devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)
        sessionQueue.async { [weak self] in
            guard let device = self?.videoInput?.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = devicePoint }
                if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = devicePoint }
                if device.isFocusModeSupported(.locked) { device.focusMode = .locked }
                if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
                device.unlockForConfiguration()
                DispatchQueue.main.async { self?.showStatus("AE/AF заблокированы") }
            } catch { }
        }
    }

    @objc private func openSettings() {
        let rawSupported = false
        let controller = ProcessingSettingsViewController(settings: settings, videoSettings: videoSettings, videoModes: availableVideoModes, exposure: exposureSlider.value, lensName: currentLensKey, rawSupported: rawSupported, deviceSummary: DeviceInfo.summary(photoOutput: photoOutput))
        controller.onSave = { [weak self] newSettings, newVideoSettings, exposure in
            guard let self else { return }; self.settings = newSettings.validated(); self.videoSettings = newVideoSettings.validated(); self.settings.save(lens: self.currentLensKey); self.videoSettings.save()
            self.exposureSlider.value = exposure; self.exposureChanged(); self.sessionQueue.async { self.applyManualControls() }
            self.profileLabel.text = self.isVideoMode ? self.videoSettings.profile.rawValue : (PremiumPresetStore.shared.preset(id: self.settings.premiumPresetID)?.name ?? self.settings.profile.rawValue)
            self.rebuildPresetCarousel(); self.applyPremiumPreview()
            if self.isVideoMode { self.sessionQueue.async { self.applyVideoConfiguration(showFallback: true) } }
            self.showStatus("Настройки применены")
        }
        let nav = UINavigationController(rootViewController: controller)
        if let sheet = nav.sheetPresentationController { sheet.detents = [.medium(), .large()]; sheet.prefersGrabberVisible = true }
        present(nav, animated: true)
    }

    private func showDeviceCapabilities() {
        guard TigrValidationTests.run() else { showStatus("Ошибка встроенной проверки настроек"); return }
        showStatus("\(DeviceInfo.shortSummary(photoOutput: photoOutput)) • VIDEO \(availableVideoModes.count) режимов")
    }

    @objc private func openGallery() {
        if movieOutput.isRecording {
            captureOneFrame(wantsRaw: false) { [weak self] frame in
                guard let self, let frame, let data = ImageEncoder.jpeg(frame.image, metadata: frame.metadata, quality: 0.94) else { return }
                self.saveCapture(processed: data, original: nil, raw: nil); DispatchQueue.main.async { self.showStatus("Фото снято без остановки видео") }
            }
            return
        }
        var configuration = PHPickerConfiguration(photoLibrary: .shared()); configuration.filter = .any(of: [.images, .videos]); configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration); picker.delegate = self; present(picker, animated: true)
    }

    private func saveCapture(processed: Data?, original: Data?, raw: Data?) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard status == .authorized || status == .limited else { DispatchQueue.main.async { self?.showStatus("Нет доступа к Фото") }; return }
            PHPhotoLibrary.shared().performChanges({
                for data in [processed, original, raw].compactMap({ $0 }) { let request = PHAssetCreationRequest.forAsset(); request.addResource(with: .photo, data: data, options: nil) }
            }) { success, _ in if !success { DispatchQueue.main.async { self?.showStatus("Ошибка сохранения") } } }
        }
    }

    private func saveVideo(_ url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard status == .authorized || status == .limited else { try? FileManager.default.removeItem(at: url); DispatchQueue.main.async { self?.showStatus("Нет доступа к Фото") }; return }
            PHPhotoLibrary.shared().performChanges({ PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url) }) { success, _ in try? FileManager.default.removeItem(at: url); DispatchQueue.main.async { self?.showStatus(success ? "Видео сохранено" : "Ошибка сохранения") } }
        }
    }

    private func showStatus(_ text: String) {
        statusLabel.text = "  \(text)  "; UIView.animate(withDuration: 0.2, animations: { self.statusLabel.alpha = 1 }) { _ in UIView.animate(withDuration: 0.35, delay: 1.5, animations: { self.statusLabel.alpha = 0 }) }
    }

    private enum CameraError: Error { case noCamera, inputUnavailable, outputUnavailable }
}

private final class FrameCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (CapturedFrame?) -> Void
    private var processedData: Data?
    private var rawData: Data?
    private var metadata: [String: Any] = [:]
    private var flashFired = false
    init(completion: @escaping (CapturedFrame?) -> Void) { self.completion = completion }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else { return }
        if photo.isRawPhoto { rawData = data } else { processedData = data; metadata = photo.metadata }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        flashFired = resolvedSettings.isFlashEnabled
        guard error == nil, let data = processedData, let image = UIImage(data: data) else { completion(nil); return }
        completion(CapturedFrame(image: image, originalData: data, rawData: rawData, metadata: metadata, flashFired: flashFired))
    }
}

private enum PhotoSceneAnalyzer {
    static func analyze(_ image: UIImage?) -> (scene: PhotoScene, brightness: Float, dynamicRange: Float) {
        guard let image, let ci = CIImage(image: image), let cg = image.cgImage else { return (.general, 0.5, 0.5) }
        let average = sample(ci, filter: "CIAreaAverage")
        let maximum = sample(ci, filter: "CIAreaMaximum")
        let minimum = sample(ci, filter: "CIAreaMinimum")
        let brightness = luma(average)
        let range = max(0, luma(maximum) - luma(minimum))

        var hasFace = false
        let face = VNDetectFaceRectanglesRequest()
        try? VNImageRequestHandler(cgImage: cg, orientation: .up).perform([face])
        hasFace = !(face.results ?? []).isEmpty
        if hasFace { return (.person, brightness, range) }
        if brightness < 0.16 { return (.night, brightness, range) }

        var labels: [String] = []
        if #available(iOS 15.0, *) {
            let classify = VNClassifyImageRequest()
            try? VNImageRequestHandler(cgImage: cg, orientation: .up).perform([classify])
            labels = (classify.results ?? []).prefix(8).filter { $0.confidence > 0.12 }.map { $0.identifier.lowercased() }
        }
        let joined = labels.joined(separator: " ")
        if joined.contains("forest") || joined.contains("tree") || joined.contains("woodland") { return (.forest, brightness, range) }
        if joined.contains("grass") || joined.contains("landscape") || joined.contains("nature") { return (.nature, brightness, range) }
        if joined.contains("sunset") || joined.contains("sunrise") { return (.sunset, brightness, range) }
        if joined.contains("sky") || joined.contains("cloud") { return (.sky, brightness, range) }
        if joined.contains("screen") || joined.contains("television") || joined.contains("monitor") { return (.screen, brightness, range) }
        if joined.contains("bicycle") || joined.contains("car") || joined.contains("vehicle") { return (.vehicle, brightness, range) }
        if joined.contains("animal") || joined.contains("dog") || joined.contains("cat") || joined.contains("bird") { return (.animal, brightness, range) }
        if joined.contains("building") || joined.contains("architecture") { return (.architecture, brightness, range) }
        if joined.contains("room") || joined.contains("indoor") || joined.contains("furniture") { return (.indoor, brightness, range) }
        if joined.contains("city") || joined.contains("street") { return (.city, brightness, range) }
        if average.1 > average.0 * 1.16 && average.1 > average.2 * 1.12 { return (.nature, brightness, range) }
        if range > 0.72 && brightness < 0.38 { return (.screen, brightness, range) }
        return (.general, brightness, range)
    }

    private static func luma(_ rgb: (Float, Float, Float)) -> Float { rgb.0 * 0.2126 + rgb.1 * 0.7152 + rgb.2 * 0.0722 }

    private static func sample(_ image: CIImage, filter: String) -> (Float, Float, Float) {
        let output = image.applyingFilter(filter, parameters: [kCIInputExtentKey: CIVector(cgRect: image.extent)])
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: NSNull()]).render(output, toBitmap: &pixel, rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return (Float(pixel[0]) / 255, Float(pixel[1]) / 255, Float(pixel[2]) / 255)
    }
}

private enum ImageEncoder {
    static func jpeg(_ image: UIImage, metadata: [String: Any], quality: CGFloat) -> Data? {
        guard let cg = image.cgImage else { return image.jpegData(compressionQuality: quality) }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        var properties = metadata
        properties[kCGImagePropertyOrientation as String] = 1
        properties[kCGImageDestinationLossyCompressionQuality as String] = quality
        CGImageDestinationAddImage(destination, cg, properties as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    static func png(_ image: UIImage, metadata: [String: Any]) -> Data? {
        guard let cg = image.cgImage else { return image.pngData() }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        var properties = metadata
        properties[kCGImagePropertyOrientation as String] = 1
        CGImageDestinationAddImage(destination, cg, properties as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}

private enum PhotoProcessor {
    static func process(_ images: [UIImage], mode: PhotoMode, settings: ProcessingSettings, context processingContext: PhotoProcessingContext) -> UIImage? {
        let renderContext = CIContext(options: [.useSoftwareRenderer: false, .cacheIntermediates: false])
        let ciImages = images.compactMap { CIImage(image: $0) }
        guard let first = ciImages.first else { return nil }
        let ranked = ciImages.map { ($0, detailScore($0, context: renderContext)) }.sorted { $0.1 > $1.1 }
        let threshold = max(0.004, (ranked.first?.1 ?? 0) * 0.38)
        var selected = ranked.filter { $0.1 >= threshold }.map(\.0)
        if selected.isEmpty { selected = [first] }
        let reference = selected[0]
        let aligned = selected.enumerated().map { index, image in index == 0 ? image.cropped(to: reference.extent) : align(image, to: reference) }
        var output = merge(aligned, reference: reference)
        output = tone(output, mode: mode, settings: adaptive(settings, mode: mode, context: processingContext), processingContext: processingContext)
        if mode == .portrait { output = portrait(output) }
        output = crop(output, aspectRatio: settings.aspectRatio)
        guard let cg = renderContext.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg, scale: images.first?.scale ?? 1, orientation: .up)
    }

    private static func detailScore(_ image: CIImage, context: CIContext) -> Float {
        let edges = image.applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 1.0])
        let average = edges.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: edges.extent)])
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(average, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return Float(pixel[0]) / 255
    }

    private static func align(_ image: CIImage, to reference: CIImage) -> CIImage {
        let request = VNTranslationalImageRegistrationRequest(targetedCIImage: image)
        let handler = VNImageRequestHandler(ciImage: reference)
        do { try handler.perform([request]); if let result = request.results?.first as? VNImageTranslationAlignmentObservation { return image.transformed(by: result.alignmentTransform).cropped(to: reference.extent) } } catch { }
        return image.cropped(to: reference.extent)
    }

    private static func merge(_ images: [CIImage], reference: CIImage) -> CIImage {
        guard images.count > 1 else { return images[0] }
        let scale = CGFloat(1.0 / Double(images.count))
        func scaled(_ image: CIImage) -> CIImage {
            image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: scale, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: scale, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: scale, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: scale)
            ])
        }
        let average = images.dropFirst().reduce(scaled(images[0])) { result, image in scaled(image).applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: result]) }
        return reference.applyingFilter("CIDissolveTransition", parameters: [kCIInputTargetImageKey: average, kCIInputTimeKey: 0.42]).cropped(to: reference.extent)
    }

    private static func adaptive(_ source: ProcessingSettings, mode: PhotoMode, context: PhotoProcessingContext) -> ProcessingSettings {
        var s = source.validated()
        let lowLight = mode == .night || context.brightness < 0.20 || context.iso > 500
        if lowLight {
            s.denoise = min(0.78, s.denoise + 0.16); s.chromaDenoise = min(0.86, s.chromaDenoise + 0.22)
            s.sharpness = max(0.18, s.sharpness - 0.14); s.highlights = min(0.88, s.highlights + 0.12)
            s.shadows = min(s.shadows + 0.08, 0.66)
        }
        if context.flash {
            s.highlights = max(s.highlights, 0.82); s.shadows = min(max(s.shadows, 0.48), 0.62)
            s.saturation = min(s.saturation, 1.02); s.denoise = max(s.denoise, 0.58); s.sharpness = min(s.sharpness, 0.34)
            s.temperature = 5400; s.automaticWhiteBalance = false
        }
        if context.lens == "0.5x" {
            s.sharpness = min(s.sharpness, 0.36)
            s.denoise = min(0.74, max(s.denoise, 0.54))
            s.chromaDenoise = min(0.80, max(s.chromaDenoise, 0.58))
            s.shadows = min(s.shadows, 0.54)
        }
        if context.frontCamera {
            s.sharpness = min(s.sharpness, 0.32)
            s.naturalSkin = true
            s.saturation = min(s.saturation, 1.05)
        }
        guard s.autoScene else { return s.validated() }
        switch context.scene {
        case .person:
            s.naturalSkin = true; s.sharpness = min(s.sharpness, 0.38); s.highlights = max(s.highlights, 0.62); s.saturation = min(s.saturation, 1.05)
        case .forest, .nature:
            s.sharpness = min(0.58, s.sharpness + 0.06); s.saturation = min(s.saturation, 1.12); s.highlights = max(s.highlights, 0.62)
        case .sunset:
            s.temperature = min(max(s.temperature, 5700), 6250); s.automaticWhiteBalance = false; s.saturation = min(s.saturation, 1.10)
        case .screen, .indoor:
            s.highlights = max(s.highlights, 0.76); s.saturation = min(s.saturation, 1.02); s.temperature = min(s.temperature, 5350)
        case .night:
            s.saturation = min(s.saturation, 1.03); s.temperature = min(max(s.temperature, 4500), 5400)
        case .sky:
            s.highlights = max(s.highlights, 0.72)
        case .architecture, .city, .vehicle:
            s.sharpness = min(0.58, s.sharpness + 0.05)
        case .animal, .general: break
        }
        return s.validated()
    }

    private static func tone(_ image: CIImage, mode: PhotoMode, settings s: ProcessingSettings, processingContext: PhotoProcessingContext) -> CIImage {
        let night = mode == .night || processingContext.scene == .night || processingContext.brightness < 0.18
        let modeBoost: Float = night ? 0.10 : (mode == .hdr ? 0.07 : 0)
        var saturation = s.saturation
        var contrast: Float = 1.015 + s.hdrStrength * 0.055
        var temperature = s.temperature
        let chosenPresetID = s.autoScene ? automaticPremiumPreset(for: processingContext.scene, fallback: s.premiumPresetID) : s.premiumPresetID
        let premium = PremiumPresetStore.shared.effective(id: chosenPresetID, intensity: s.presetIntensity, lens: processingContext.frontCamera ? "front" : processingContext.lens, iso: processingContext.iso, faceAware: processingContext.scene == .person || processingContext.frontCamera)
        let premiumParameters = premium?.1 ?? PremiumPresetParameters()
        switch s.profile {
        case .natural: contrast = min(contrast, 1.065)
        case .forestGolden: temperature = max(temperature, 5900); contrast += 0.025
        case .cinematic: contrast += 0.055; saturation = min(saturation, 1.05)
        case .hdrNatural: contrast = min(contrast, 1.055)
        }
        if night { contrast = min(contrast, 1.06); saturation = min(saturation, 1.04) }
        if chosenPresetID == PremiumPresetID.off.rawValue {
            contrast = 1.0; saturation = 1.0; temperature = 5200
        } else {
            contrast += premiumParameters.contrast * 0.48 + premiumParameters.dehaze * 0.22
            saturation *= 1 + premiumParameters.saturation
            temperature += premiumParameters.temperatureKelvinOffset
        }
        let luminanceNoise = min(0.095, 0.008 + max(s.denoise, premiumParameters.noiseReduction) * 0.065 + max(0, processingContext.iso - 400) / 18_000)
        let chromaPass = min(0.06, 0.006 + s.chromaDenoise * 0.045)
        var result = image.applyingFilter("CINoiseReduction", parameters: ["inputNoiseLevel": luminanceNoise, "inputSharpness": 0.28])
        result = result.applyingFilter("CINoiseReduction", parameters: ["inputNoiseLevel": chromaPass, "inputSharpness": 0.18])
        let cleanBeforeSharpen = result
        if premiumParameters.exposure != 0 { result = result.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: premiumParameters.exposure]) }
        result = result.applyingFilter("CIHighlightShadowAdjust", parameters: [
            "inputShadowAmount": min(0.78, s.shadows + modeBoost + max(0, premiumParameters.shadows) * 0.42),
            "inputHighlightAmount": max(0.16, 1 - (s.highlights + abs(min(0, premiumParameters.highlights)) * 0.55) * (s.preserveSky ? 0.86 : 0.62))
        ])
        let premiumBrightness = (premiumParameters.whites + premiumParameters.blacks) * 0.035
        result = result.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: saturation, kCIInputContrastKey: contrast, kCIInputBrightnessKey: (night ? -0.008 : 0) + premiumBrightness])
        result = result.applyingFilter("CIVibrance", parameters: ["inputAmount": (s.profile == .forestGolden ? 0.12 : 0.045) + premiumParameters.vibrance])
        let targetTemperature = s.automaticWhiteBalance ? automaticTemperature(scene: processingContext.scene, brightness: processingContext.brightness) : temperature
        let tint: CGFloat = ((processingContext.scene == .indoor || processingContext.scene == .screen) ? -2.0 : 0) + CGFloat(premiumParameters.tint * 100)
        result = result.applyingFilter("CITemperatureAndTint", parameters: ["inputNeutral": CIVector(x: 5200, y: 0), "inputTargetNeutral": CIVector(x: CGFloat(targetTemperature), y: tint)])
        result = applyPremiumColor(result, presetID: chosenPresetID, amount: s.presetIntensity)
        let edgeSharpness = min(0.60, s.sharpness + premiumParameters.sharpening + premiumParameters.texture * 0.24 + premiumParameters.clarity * 0.18)
        result = result.applyingFilter("CIUnsharpMask", parameters: [kCIInputRadiusKey: 1.20, kCIInputIntensityKey: min(0.34, edgeSharpness * 0.40)])
        result = result.applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: 0.06 + edgeSharpness * 0.52])
        if premiumParameters.vignette < 0 {
            result = result.applyingFilter("CIVignette", parameters: [kCIInputIntensityKey: abs(premiumParameters.vignette) * 1.5, kCIInputRadiusKey: min(result.extent.width, result.extent.height) * 0.72])
        }
        if s.naturalSkin, let mask = faceMask(for: image) {
            let skin = cleanBeforeSharpen
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: min(saturation, 1.025), kCIInputContrastKey: 1.01])
                .applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: 0.12])
            result = skin.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: result, kCIInputMaskImageKey: mask])
        }
        return result.cropped(to: image.extent)
    }

    private static func automaticPremiumPreset(for scene: PhotoScene, fallback: String) -> String {
        switch scene {
        case .forest, .nature: return PremiumPresetID.forestSignature.rawValue
        case .sunset: return PremiumPresetID.goldenHourElite.rawValue
        case .person, .animal: return PremiumPresetID.canonPortraitPro.rawValue
        case .night, .indoor: return PremiumPresetID.cinemaNight.rawValue
        case .vehicle, .architecture: return PremiumPresetID.sonyDetailPro.rawValue
        case .sky, .city, .general, .screen: return fallback
        }
    }

    private static func applyPremiumColor(_ image: CIImage, presetID: String, amount: Float) -> CIImage {
        let t = amount.clamped(0, 1)
        guard t > 0.001 else { return image }
        switch PremiumPresetID(rawValue: presetID) {
        case .forestSignature:
            return image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1.0, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: CGFloat(1 - 0.035 * t), z: CGFloat(0.015 * t), w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(1 + 0.035 * t), w: 0)
            ])
        case .cinematicTealSoft:
            return image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: CGFloat(1 + 0.025 * t), y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: CGFloat(1 + 0.018 * t), z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: CGFloat(0.012 * t), z: CGFloat(1 + 0.055 * t), w: 0),
                "inputBiasVector": CIVector(x: CGFloat(0.006 * t), y: 0, z: CGFloat(0.010 * t), w: 0)
            ])
        case .leicaInspired:
            return image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1 - 0.025 * t, kCIInputContrastKey: 1 + 0.025 * t])
        default: return image
        }
    }

    private static func crop(_ image: CIImage, aspectRatio: String) -> CIImage {
        let target: CGFloat
        switch aspectRatio { case "16:9": target = 9.0 / 16.0; case "1:1": target = 1; default: target = 3.0 / 4.0 }
        let extent = image.extent
        let current = extent.width / extent.height
        if abs(current - target) < 0.001 { return image }
        let rect: CGRect
        if current > target {
            let width = extent.height * target
            rect = CGRect(x: extent.midX - width / 2, y: extent.minY, width: width, height: extent.height)
        } else {
            let height = extent.width / target
            rect = CGRect(x: extent.minX, y: extent.midY - height / 2, width: extent.width, height: height)
        }
        return image.cropped(to: rect)
    }

    private static func automaticTemperature(scene: PhotoScene, brightness: Float) -> Float {
        switch scene {
        case .sunset: return 5850
        case .forest, .nature: return brightness > 0.40 ? 5400 : 5200
        case .indoor, .screen: return 4950
        case .night: return 4700
        default: return 5200
        }
    }

    private static func faceMask(for image: CIImage) -> CIImage? {
        let request = VNDetectFaceRectanglesRequest()
        do { try VNImageRequestHandler(ciImage: image, orientation: .up).perform([request]) } catch { return nil }
        guard let faces = request.results, !faces.isEmpty else { return nil }
        var mask: CIImage?
        for face in faces {
            let box = face.boundingBox
            let center = CIVector(x: image.extent.minX + box.midX * image.extent.width, y: image.extent.minY + box.midY * image.extent.height)
            let radius = max(box.width * image.extent.width, box.height * image.extent.height) * 0.68
            let radial = CIFilter(name: "CIRadialGradient", parameters: ["inputCenter": center, "inputRadius0": radius * 0.42, "inputRadius1": radius, "inputColor0": CIColor.white, "inputColor1": CIColor.clear])?.outputImage?.cropped(to: image.extent)
            if let radial { mask = mask.map { radial.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: $0]) } ?? radial }
        }
        return mask
    }

    private static func portrait(_ image: CIImage) -> CIImage {
        let request = VNGeneratePersonSegmentationRequest(); request.qualityLevel = .balanced; request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        do {
            try VNImageRequestHandler(ciImage: image).perform([request])
            guard let buffer = request.results?.first?.pixelBuffer else { return image }
            let rawMask = CIImage(cvPixelBuffer: buffer)
            let mask = rawMask.transformed(by: CGAffineTransform(scaleX: image.extent.width / rawMask.extent.width, y: image.extent.height / rawMask.extent.height)).cropped(to: image.extent)
            let background = image.clampedToExtent().applyingGaussianBlur(sigma: 14).cropped(to: image.extent)
            return image.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: background, kCIInputMaskImageKey: mask]).cropped(to: image.extent)
        } catch { return image }
    }
}

private enum VideoPostProcessor {
    static func process(_ sourceURL: URL, settings: VideoSettings, thermalState: ProcessInfo.ThermalState, completion: @escaping (URL) -> Void) {
        let safe = settings.validated()
        guard !safe.hdrEnabled, safe.preset != .longRecord, thermalState != .serious, thermalState != .critical else {
            completion(sourceURL); return
        }
        let asset = AVAsset(url: sourceURL)
        let composition = AVMutableVideoComposition(asset: asset, applyingCIFiltersWithHandler: { request in
            autoreleasepool {
                let source = request.sourceImage.clampedToExtent()
                let output = applyProfile(source, settings: safe).cropped(to: request.sourceImage.extent)
                request.finish(with: output, context: nil)
            }
        })
        let preset = safe.codec == .hevc ? AVAssetExportPresetHEVCHighestQuality : AVAssetExportPresetHighestQuality
        guard let export = AVAssetExportSession(asset: asset, presetName: preset) else { completion(sourceURL); return }
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("TigrProcessed-\(UUID().uuidString).mov")
        export.outputURL = target; export.outputFileType = .mov; export.videoComposition = composition; export.shouldOptimizeForNetworkUse = false
        export.exportAsynchronously {
            if export.status == .completed {
                try? FileManager.default.removeItem(at: sourceURL); completion(target)
            } else {
                try? FileManager.default.removeItem(at: target); completion(sourceURL)
            }
        }
    }

    private static func applyProfile(_ image: CIImage, settings s: VideoSettings) -> CIImage {
        var saturation = s.saturation, contrast: Float = 1.025, temperature = s.temperature
        var noise = s.noiseReduction, sharpness = s.sharpness
        switch s.profile {
        case .natural: saturation = min(saturation, 1.04); contrast = 1.025
        case .forestGolden: saturation = min(max(saturation, 1.06), 1.12); contrast = 1.045; temperature = max(5800, temperature)
        case .cinematic: saturation = min(saturation, 1.05); contrast = 1.075; temperature = max(5400, min(5900, temperature))
        case .hdrNatural: saturation = min(saturation, 1.06); contrast = 1.035
        case .lowLight: saturation = min(saturation, 1.02); contrast = 1.035; noise = min(0.78, noise + 0.18); sharpness = max(0.12, sharpness - 0.14); temperature = min(5200, temperature)
        }
        var result = image.applyingFilter("CINoiseReduction", parameters: ["inputNoiseLevel": 0.006 + noise * 0.045, "inputSharpness": 0.20])
        result = result.applyingFilter("CIHighlightShadowAdjust", parameters: ["inputShadowAmount": s.profile == .lowLight ? 0.32 : 0.20, "inputHighlightAmount": s.preserveSky ? 0.58 : 0.72])
        result = result.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: saturation, kCIInputContrastKey: contrast])
        result = result.applyingFilter("CITemperatureAndTint", parameters: ["inputNeutral": CIVector(x: 5200, y: 0), "inputTargetNeutral": CIVector(x: CGFloat(temperature), y: 0)])
        result = result.applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: min(0.42, 0.06 + sharpness * 0.52)])
        return result
    }
}

private final class ProcessingSettingsViewController: UIViewController, UIDocumentPickerDelegate {
    var onSave: ((ProcessingSettings, VideoSettings, Float) -> Void)?
    private var settings: ProcessingSettings
    private var videoSettings: VideoSettings
    private let videoModes: [VideoMode]
    private var exposure: Float
    private let lensName: String
    private let rawSupported: Bool
    private let deviceSummary: String
    private let stack = UIStackView()

    init(settings: ProcessingSettings, videoSettings: VideoSettings, videoModes: [VideoMode], exposure: Float, lensName: String, rawSupported: Bool, deviceSummary: String) { self.settings = settings; self.videoSettings = videoSettings; self.videoModes = videoModes; self.exposure = exposure; self.lensName = lensName; self.rawSupported = rawSupported; self.deviceSummary = deviceSummary; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground; title = "LIB PATCHER • \(lensName)"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Готово", style: .done, target: self, action: #selector(done))
        let scroll = UIScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(scroll)
        stack.translatesAutoresizingMaskIntoConstraints = false; stack.axis = .vertical; stack.spacing = 14; stack.isLayoutMarginsRelativeArrangement = true; stack.layoutMargins = .init(top: 18, left: 18, bottom: 30, right: 18); scroll.addSubview(stack)
        NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor), scroll.topAnchor.constraint(equalTo: view.topAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor), stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor), stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor), stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor), stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor), stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)])

        let info = UILabel(); info.numberOfLines = 0; info.font = .systemFont(ofSize: 13); info.textColor = .secondaryLabel; info.text = deviceSummary; stack.addArrangedSubview(info)
        let configRow = UIStackView(); configRow.axis = .horizontal; configRow.distribution = .fillEqually; configRow.spacing = 8
        let importButton = UIButton(type: .system); importButton.setTitle("Импорт JSON", for: .normal); importButton.addTarget(self, action: #selector(importConfig), for: .touchUpInside)
        let exportButton = UIButton(type: .system); exportButton.setTitle("Экспорт фото", for: .normal); exportButton.addTarget(self, action: #selector(exportConfig), for: .touchUpInside)
        let exportVideoButton = UIButton(type: .system); exportVideoButton.setTitle("Экспорт видео", for: .normal); exportVideoButton.addTarget(self, action: #selector(exportVideoConfig), for: .touchUpInside)
        configRow.addArrangedSubview(importButton); configRow.addArrangedSubview(exportButton); configRow.addArrangedSubview(exportVideoButton); stack.addArrangedSubview(configRow)

        addHeader("ОБРАБОТКА ФОТО")
        let premiumPresets = PremiumPresetStore.shared.all
        let premiumName = PremiumPresetStore.shared.preset(id: settings.premiumPresetID)?.name ?? "FULL FRAME PRO"
        addMenuButton(title: "Премиум-пресет: \(premiumName)", items: premiumPresets.map(\.name)) { [weak self] index, button in
            guard let self, premiumPresets.indices.contains(index) else { return }
            self.settings.premiumPresetID = premiumPresets[index].id
            PremiumPresetStore.shared.select(premiumPresets[index].id)
            button.setTitle("Премиум-пресет: \(premiumPresets[index].name)", for: .normal)
        }
        addSlider("Интенсивность пресета", 0, 1, settings.presetIntensity, valueText: { "\(Int($0 * 100))%" }) {
            self.settings.presetIntensity = $0; PremiumPresetStore.shared.intensity = $0
        }
        let profileDescription = UILabel(); profileDescription.numberOfLines = 0; profileDescription.font = .systemFont(ofSize: 12); profileDescription.textColor = .secondaryLabel; profileDescription.text = settings.profile.details; stack.addArrangedSubview(profileDescription)
        let profiles = UISegmentedControl(items: ["NATURAL", "FOREST", "CINEMA", "HDR"])
        profiles.selectedSegmentIndex = ProcessingProfile.allCases.firstIndex(of: settings.profile) ?? 0
        profiles.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            let profile = ProcessingProfile.allCases[profiles.selectedSegmentIndex]
            let preset = ProcessingSettings.preset(profile, preserving: self.settings)
            self.settings = preset.0; self.exposure = preset.1; profileDescription.text = profile.details
        }, for: .valueChanged)
        stack.addArrangedSubview(profiles)
        addSwitch("Автоматическое определение сцены", settings.autoScene) { self.settings.autoScene = $0 }
        addSwitch("Быстрая съёмка", settings.fastCapture) { self.settings.fastCapture = $0 }
        addHeader("Объединение кадров")
        let frameValues = [6, 10, 12, 14, 16]
        let frames = UISegmentedControl(items: frameValues.map(String.init)); frames.selectedSegmentIndex = frameValues.enumerated().min(by: { abs($0.element - settings.frameCount) < abs($1.element - settings.frameCount) })?.offset ?? 1; frames.addAction(UIAction { [weak self] _ in self?.settings.frameCount = frameValues[frames.selectedSegmentIndex] }, for: .valueChanged); stack.addArrangedSubview(frames)
        addSlider("Сила HDR", 0, 1, settings.hdrStrength) { self.settings.hdrStrength = $0 }
        addSlider("Базовая экспозиция", -2, 2, exposure, valueText: { String(format: "%+.2f EV", $0) }) { self.exposure = $0 }
        addSlider("Шумоподавление", 0, 1, settings.denoise) { self.settings.denoise = $0 }
        addSlider("Цветной шум", 0, 1, settings.chromaDenoise) { self.settings.chromaDenoise = $0 }
        addSlider("Резкость", 0, 0.75, settings.sharpness) { self.settings.sharpness = $0 }
        addSlider("Насыщенность", 0.75, 1.25, settings.saturation) { self.settings.saturation = $0 }
        addSlider("Светлые участки", 0, 1, settings.highlights) { self.settings.highlights = $0 }
        addSlider("Детализация теней", 0, 1, settings.shadows) { self.settings.shadows = $0 }
        addSwitch("Автоматический баланс белого", settings.automaticWhiteBalance) { self.settings.automaticWhiteBalance = $0 }
        addMenuButton(title: "Баланс белого: \(settings.whiteBalancePreset)", items: ["Авто", "Солнце", "Облачно", "Лампа", "Неон"]) { [weak self] index, button in
            guard let self else { return }; let names = ["Авто", "Солнце", "Облачно", "Лампа", "Неон"]
            let values: [Float] = [5200, 5500, 6500, 3200, 4300]
            self.settings.whiteBalancePreset = names[index]; self.settings.temperature = values[index]
            self.settings.automaticWhiteBalance = index == 0; button.setTitle("Баланс белого: \(names[index])", for: .normal)
        }
        addSlider("Температура", 3200, 7500, settings.temperature, valueText: { "\(Int($0)) K" }) { self.settings.temperature = $0; self.settings.automaticWhiteBalance = false }
        addSwitch("Сохранять небо и яркие лампы", settings.preserveSky) { self.settings.preserveSky = $0 }
        addSwitch("Натуральный оттенок кожи", settings.naturalSkin) { self.settings.naturalSkin = $0 }
        addSwitch("Сохранять исходный кадр", settings.saveOriginal) { self.settings.saveOriginal = $0 }
        addSwitch("Сохранять обработанное фото", settings.saveProcessed) { self.settings.saveProcessed = $0 }
        addSwitch("Сохранять обработанное фото в PNG", settings.savePNG) { self.settings.savePNG = $0 }
        addSwitch("Зеркальная фронтальная камера", settings.mirrorFront) { self.settings.mirrorFront = $0 }
        addSwitch("RAW/ProRAW — недоступно на стандартном iPhone 12", false, enabled: false) { _ in }
        addMenuButton(title: "Соотношение сторон: \(settings.aspectRatio)", items: ["4:3", "16:9", "1:1"]) { [weak self] index, button in
            guard let self else { return }; let values = ["4:3", "16:9", "1:1"]; self.settings.aspectRatio = values[index]; button.setTitle("Соотношение сторон: \(values[index])", for: .normal)
        }

        addHeader("Цветовой профиль")
        let styles = UISegmentedControl(items: ["День", "Ночь", "Люди", "Природа"]); styles.selectedSegmentIndex = settings.style; styles.addAction(UIAction { [weak self] _ in self?.settings.style = styles.selectedSegmentIndex }, for: .valueChanged); stack.addArrangedSubview(styles)

        addHeader("Ручное управление")
        addSwitch("Включить Pro-режим", settings.manualEnabled) { self.settings.manualEnabled = $0 }
        addSlider("ISO", 25, 3200, settings.iso, valueText: { "\(Int($0))" }) { self.settings.iso = $0 }
        addSlider("Выдержка", 1.0/8000.0, 1, settings.shutterSeconds, valueText: { $0 >= 0.5 ? String(format: "%.1f с", $0) : "1/\(max(1, Int(1 / $0))) с" }) { self.settings.shutterSeconds = $0 }
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

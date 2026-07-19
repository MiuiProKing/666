import AVFoundation
import CoreImage
import Photos
import PhotosUI
import UIKit
import UniformTypeIdentifiers
import Vision

private enum PhotoMode: Int, CaseIterable {
    case normal, hdr, night, portrait

    var title: String {
        switch self {
        case .normal: return "ÐžÐ±Ñ‹Ñ‡Ð½Ñ‹Ð¹"
        case .hdr: return "HDR+"
        case .night: return "ÐÐ¾Ñ‡ÑŒ"
        case .portrait: return "ÐŸÐ¾Ñ€Ñ‚Ñ€ÐµÑ‚"
        }
    }
}

private struct ProcessingSettings: Codable {
    var frameCount = 5
    var hdrStrength: Float = 0.65
    var denoise: Float = 0.55
    var sharpness: Float = 0.45
    var saturation: Float = 1.02
    var highlights: Float = 0.55
    var shadows: Float = 0.55
    var temperature: Float = 6500
    var preserveSky = true
    var naturalSkin = true
    var saveOriginal = false
    var rawEnabled = false
    var style = 0
    var manualEnabled = false
    var iso: Float = 100
    var shutterSeconds: Float = 1.0 / 60.0
    var focus: Float = 0.5
    var whiteBalance: Float = 5200

    static func load(lens: String = "1x") -> ProcessingSettings {
        let d = UserDefaults.standard
        if let data = d.data(forKey: "lens.settings.\(lens)"), let value = try? JSONDecoder().decode(ProcessingSettings.self, from: data) { return value }
        guard d.bool(forKey: "settings.saved") else { return ProcessingSettings() }
        var s = ProcessingSettings()
        s.frameCount = d.integer(forKey: "frames")
        s.hdrStrength = d.float(forKey: "hdr")
        s.denoise = d.float(forKey: "denoise")
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
        return s
    }

    func save(lens: String = "1x") {
        let d = UserDefaults.standard
        if let data = try? JSONEncoder().encode(self) { d.set(data, forKey: "lens.settings.\(lens)") }
        d.set(true, forKey: "settings.saved")
        d.set(frameCount, forKey: "frames")
        d.set(hdrStrength, forKey: "hdr")
        d.set(denoise, forKey: "denoise")
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
    var name: String
    var frames: Int
    var exposure: Float
    var hdrStrength: Float
    var shadows: Float
    var highlights: Float
    var sharpness: Float
    var noiseReduction: Float
    var saturation: Float
    var temperature: Float
    var preserveSky: Bool
    var naturalSkin: Bool
    var chromaNoiseReduction: Float

    init(settings: ProcessingSettings, exposure: Float, name: String = "Tigr Style") {
        self.name = name; frames = settings.frameCount; self.exposure = exposure; hdrStrength = settings.hdrStrength
        shadows = settings.shadows; highlights = settings.highlights; sharpness = settings.sharpness
        noiseReduction = settings.denoise; saturation = settings.saturation; temperature = settings.temperature
        preserveSky = settings.preserveSky; naturalSkin = settings.naturalSkin; chromaNoiseReduction = settings.denoise
    }

    func applied(to source: ProcessingSettings) -> ProcessingSettings {
        var s = source; s.frameCount = [3, 5, 8, 12].min(by: { abs($0 - frames) < abs($1 - frames) }) ?? 5
        s.hdrStrength = hdrStrength; s.shadows = shadows; s.highlights = highlights; s.sharpness = sharpness
        s.denoise = max(noiseReduction, chromaNoiseReduction); s.saturation = saturation; s.temperature = temperature
        s.preserveSky = preserveSky; s.naturalSkin = naturalSkin; return s
    }
}

private struct CapturedFrame {
    let image: UIImage
    let originalData: Data
    let rawData: Data?
}

private final class SeriesAccumulator { var frames: [CapturedFrame] = [] }

final class CameraViewController: UIViewController {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.tigr.camera.session", qos: .userInitiated)
    private let processingQueue = DispatchQueue(label: "com.tigr.camera.processing", qos: .userInitiated)
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
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
    private let statusLabel = UILabel()
    private let gridView = GridOverlayView()
    private let focusRing = UIView()
    private let zoomStack = UIStackView()

    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        buildInterface()
        requestCameraPermission()
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
    }

    private func buildInterface() {
        previewView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewView)
        previewView.layer.addSublayer(previewLayer)
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
        for (title, tag) in [("0.5Ã—", 5), ("1Ã—", 10), ("2Ã—", 20)] {
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
        previewView.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinchZoom(_:))))

        NSLayoutConstraint.activate([
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor), previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewView.topAnchor.constraint(equalTo: view.topAnchor), previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            gridView.leadingAnchor.constraint(equalTo: previewView.leadingAnchor), gridView.trailingAnchor.constraint(equalTo: previewView.trailingAnchor),
            gridView.topAnchor.constraint(equalTo: previewView.topAnchor), gridView.bottomAnchor.constraint(equalTo: previewView.bottomAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor), topBar.trailing÷¾ù¶‰žËkºwµçd€´ø%%µ…”ì(€€€€€€€Õ…É¥µ…•Ì¹½Õ¹Ð€ø€Ä•±Í”ìÉ•ÑÕÉ¸¥µ…•ÍlÁtô(€€€€€€€±•ÐÍ…±”€ô±½…Ð Ä¸À€¼½Õ‰±”¡¥µ…•Ì¹½Õ¹Ð¤¤(€€€€€€€™Õ¹ŒÍ…±•¡|¥µ…”è%%µ…”¤€´ø%%µ…”ì(€€€€€€€€€€€¥µ…”¹…ÁÁ±å¥¹¥±Ñ•È ‰%½±½É5…ÑÉ¥àˆ°Á…É…µ•Ñ•ÉÌèl(€€€€€€€€€€€€€€€€‰¥¹ÁÕÑIY•Ñ½Èˆè%Y•Ñ½È¡àèÍ…±”°äè€À°èè€À°Üè€À¤°€‰¥¹ÁÕÑY•Ñ½Èˆè%Y•Ñ½È¡àè€À°äèÍ…±”°èè€À°Üè€À¤°(€€€€€€€€€€€€€€€€‰¥¹ÁÕÑ	Y•Ñ½Èˆè%Y•Ñ½È¡àè€À°äè€À°èèÍ…±”°Üè€À¤°€‰¥¹ÁÕÑY•Ñ½Èˆè%Y•Ñ½È¡àè€À°äè€À°èè€À°ÜèÍ…±”¤(€€€€€€€€€€€t¤(€€€€€€€ô(€€€€€€€É•ÑÕÉ¸¥µ…•Ì¹‘É½Á¥ÉÍÐ ¤¹É•‘Õ”¡Í…±•¡¥µ…•ÍlÁt¤¤ìÉ•ÍÕ±Ð°¥µ…”¥¸Í…±•¡¥µ…”¤¹…ÁÁ±å¥¹¥±Ñ•È ‰%‘‘¥Ñ¥½¹½µÁ½Í¥Ñ¥¹œˆ°Á…É…µ•Ñ•ÉÌèm­%%¹ÁÕÑ	…­É½Õ¹‘%µ…•-•äèÉ•ÍÕ±Ñt¤ô(€€€ô((€€€ÁÉ¥Ù…Ñ”ÍÑ…Ñ¥Œ™Õ¹ŒÑ½¹”¡|¥µ…”è%%µ…”°µ½‘”èA¡½Ñ½5½‘”°Í•ÑÑ¥¹ÌÌèAÉ½•ÍÍ¥¹M•ÑÑ¥¹Ì¤€´ø%%µ…”ì(€€€€€€€±•Ðµ½‘•	½½ÍÐè±½…Ð€ôµ½‘”€ôô€¹¹¥¡Ð€ü€À¸ÈÔ€è€¡µ½‘”€ôô€¹¡‘È€ü€À¸ÄÈ€è€À¤(€€€€€€€Ù…ÈÍ…ÑÕÉ…Ñ¥½¸€ôÌ¹Í…ÑÕÉ…Ñ¥½¸(€€€€€€€Ù…È½¹ÑÉ…ÍÐè±½…Ð€ô€Ä¸ÀÌ€¬Ì¹¡‘ÉMÑÉ•¹Ñ €¨€À¸Àà(€€€€€€€Ù…ÈÑ•µÁ•É…ÑÕÉ”€ôÌ¹Ñ•µÁ•É…ÑÕÉ”(€€€€€€€ÍÝ¥Ñ Ì¹ÍÑå±”ì…Í”€ÄèÑ•µÁ•É…ÑÕÉ”€´ô€ÈÔÀì½¹ÑÉ…ÍÐ€¬ô€À¸ÀÐì…Í”€ÈèÍ…ÑÕÉ…Ñ¥½¸€´ô€À¸ÀÔìÑ•µÁ•É…ÑÕÉ”€¬ô€ÄÈÀì…Í”€ÌèÍ…ÑÕÉ…Ñ¥½¸€¬ô€À¸ÄÈì½¹ÑÉ…ÍÐ€¬ô€À¸ÀÌì‘•™…Õ±Ðè‰É•…¬ô(€€€€€€€Ù…ÈÉ•ÍÕ±Ð€ô¥µ…”¹…ÁÁ±å¥¹¥±Ñ•È ‰%9½¥Í•I•‘ÕÑ¥½¸ˆ°Á…É…µ•Ñ•ÉÌèl‰¥¹ÁÕÑ9½¥Í•1•Ù•°ˆè€À¸ÀÄÔ€¬Ì¹‘•¹½¥Í”€¨€À¸ÀÜ°€‰¥¹ÁÕÑM¡…ÉÁ¹•ÍÌˆè€À¸ÌÕt¤(€€€€€€€É•ÍÕ±Ð€ôÉ•ÍÕ±Ð¹…ÁÁ±å¥¹¥±Ñ•È ‰%!¥¡±¥¡ÑM¡…‘½Ý‘©ÕÍÐˆ°Á…É…µ•Ñ•ÉÌèl‰¥¹ÁÕÑM¡…‘½Ýµ½Õ¹Ðˆèµ¥¸ Ä°Ì¹Í¡…‘½ÝÌ€¬µ½‘•	½½ÍÐ¤°€‰¥¹ÁÕÑ!¥¡±¥¡Ñµ½Õ¹Ðˆèµ…à À¸ÈÔ°€Ä€´Ì¹¡¥¡±¥¡ÑÌ€¨€¡Ì¹ÁÉ•Í•ÉÙ•M­ä€ü€À¸àÔ€è€À¸ÔÔ¤¥t¤(€€€€€€€É•ÍÕ±Ð€ôÉ•ÍÕ±Ð¹…ÁÁ±å¥¹¥±Ñ•È ‰%½±½É½¹ÑÉ½±Ìˆ°Á…É…µ•Ñ•ÉÌèm­%%¹ÁÕÑM…ÑÕÉ…Ñ¥½¹-•äèÍ…ÑÕÉ…Ñ¥½¸°­%%¹ÁÕÑ½¹ÑÉ…ÍÑ-•äè½¹ÑÉ…ÍÐ°­%%¹ÁÕÑ	É¥¡Ñ¹•ÍÍ-•äèµ½‘”€ôô€¹¹¥¡Ð€ü€À¸ÀÈÔ€è€Át¤(€€€€€€€É•ÍÕ±Ð€ôÉ•ÍÕ±Ð¹…ÁÁ±å¥¹¥±Ñ•È ‰%M¡…ÉÁ•¹1Õµ¥¹…¹”ˆ°Á…É…µ•Ñ•ÉÌèm­%%¹ÁÕÑM¡…ÉÁ¹•ÍÍ-•äè€À¸ÄÔ€¬Ì¹Í¡…ÉÁ¹•ÍÌ€¨€À¸åt¤(€€€€€€€É•ÍÕ±Ð€ôÉ•ÍÕ±Ð¹…ÁÁ±å¥¹¥±Ñ•È ‰%Q•µÁ•É…ÑÕÉ•¹‘Q¥¹Ðˆ°Á…É…µ•Ñ•ÉÌèl‰¥¹ÁÕÑ9•ÕÑÉ…°ˆè%Y•Ñ½È¡àè€ØÔÀÀ°äè€À¤°€‰¥¹ÁÕÑQ…É•Ñ9•ÕÑÉ…°ˆè%Y•Ñ½È¡àè±½…Ð¡Ñ•µÁ•É…ÑÕÉ”¤°äèÌ¹¹…ÑÕÉ…±M­¥¸€ü€À€è€Ì¥t¤(€€€€€€€É•ÑÕÉ¸É•ÍÕ±Ð¹É½ÁÁ•¡Ñ¼è¥µ…”¹•áÑ•¹Ð¤(€€€ô((€€€ÁÉ¥Ù…Ñ”ÍÑ…Ñ¥Œ™Õ¹ŒÁ½ÉÑÉ…¥Ð¡|¥µ…”è%%µ…”¤€´ø%%µ…”ì(€€€€€€€±•ÐÉ•ÅÕ•ÍÐ€ôY9•¹•É…Ñ•A•ÉÍ½¹M•µ•¹Ñ…Ñ¥½¹I•ÅÕ•ÍÐ ¤ìÉ•ÅÕ•ÍÐ¹ÅÕ…±¥Ñå1•Ù•°€ô€¹‰…±…¹•ìÉ•ÅÕ•ÍÐ¹½ÕÑÁÕÑA¥á•±½Éµ…Ð€ô­YA¥á•±½Éµ…ÑQåÁ•}=¹•½µÁ½¹•¹Ðà(€€€€€€€‘¼ì(€€€€€€€€€€€ÑÉäY9%µ…•I•ÅÕ•ÍÑ!…¹‘±•È¡¥%µ…”è¥µ…”¤¹Á•É™½É´¡mÉ•ÅÕ•ÍÑt¤(€€€€€€€€€€€Õ…É±•Ð‰Õ™™•È€ôÉ•ÅÕ•ÍÐ¹É•ÍÕ±ÑÌü¹™¥ÉÍÐü¹Á¥á•±	Õ™™•È•±Í”ìÉ•ÑÕÉ¸¥µ…”ô(€€€€€€€€€€€±•ÐÉ…Ý5…Í¬€ô%%µ…”¡ÙA¥á•±	Õ™™•Èè‰Õ™™•È¤(€€€€€€€€€€€±•Ðµ…Í¬€ôÉ…Ý5…Í¬¹ÑÉ…¹Í™½Éµ•¡‰äè™™¥¹•QÉ…¹Í™½É´¡Í…±•`è¥µ…”¹•áÑ•¹Ð¹Ý¥‘Ñ €¼É…Ý5…Í¬¹•áÑ•¹Ð¹Ý¥‘Ñ °äè¥µ…”¹•áÑ•¹Ð¹¡•¥¡Ð€¼É…Ý5…Í¬¹•áÑ•¹Ð¹¡•¥¡Ð¤¤¹É½ÁÁ•¡Ñ¼è¥µ…”¹•áÑ•¹Ð¤(€€€€€€€€€€€±•Ð‰…­É½Õ¹€ô¥µ…”¹±…µÁ•‘Q½áÑ•¹Ð ¤¹…ÁÁ±å¥¹…ÕÍÍ¥…¹	±ÕÈ¡Í¥µ„è€ÄÐ¤¹É½ÁÁ•¡Ñ¼è¥µ…”¹•áÑ•¹Ð¤(€€€€€€€€€€€É•ÑÕÉ¸¥µ…”¹…ÁÁ±å¥¹¥±Ñ•È ‰%	±•¹‘]¥Ñ¡5…Í¬ˆ°Á…É…µ•Ñ•ÉÌèm­%%¹ÁÕÑ	…­É½Õ¹‘%µ…•-•äè‰…­É½Õ¹°­%%¹ÁÕÑ5…Í­%µ…•-•äèµ…Í­t¤¹É½ÁÁ•¡Ñ¼è¥µ…”¹•áÑ•¹Ð¤(€€€€€€€ô…Ñ ìÉ•ÑÕÉ¸¥µ…”ô(€€€ô)ô()ÁÉ¥Ù…Ñ”™¥¹…°±…ÍÌAÉ½•ÍÍ¥¹M•ÑÑ¥¹ÍY¥•Ý½¹ÑÉ½±±•ÈèU%Y¥•Ý½¹ÑÉ½±±•È°U%½Õµ•¹ÑA¥­•É•±•…Ñ”ì(€€€Ù…È½¹M…Ù”è€ ¡AÉ½•ÍÍ¥¹M•ÑÑ¥¹Ì°±½…Ð¤€´øY½¥¤ü(€€€ÁÉ¥Ù…Ñ”Ù…ÈÍ•ÑÑ¥¹ÌèAÉ½•ÍÍ¥¹M•ÑÑ¥¹Ì(€€€ÁÉ¥Ù…Ñ”Ù…È•áÁ½ÍÕÉ”è±½…Ð(€€€ÁÉ¥Ù…Ñ”±•Ð±•¹Í9…µ”èMÑÉ¥¹œ(€€€ÁÉ¥Ù…Ñ”±•ÐÉ…ÝMÕÁÁ½ÉÑ•è	½½°(€€€ÁÉ¥Ù…Ñ”±•Ð‘•Ù¥•MÕµµ…ÉäèMÑÉ¥¹œ(€€€ÁÉ¥Ù…Ñ”±•ÐÍÑ…¬€ôU%MÑ…­Y¥•Ü ¤((€€€¥¹¥Ð¡Í•ÑÑ¥¹ÌèAÉ½•ÍÍ¥¹M•ÑÑ¥¹Ì°•áÁ½ÍÕÉ”è±½…Ð°±•¹Í9…µ”èMÑÉ¥¹œ°É…ÝMÕÁÁ½ÉÑ•è	½½°°‘•Ù¥•MÕµµ…ÉäèMÑÉ¥¹œ¤ìÍ•±˜¹Í•ÑÑ¥¹Ì€ôÍ•ÑÑ¥¹ÌìÍ•±˜¹•áÁ½ÍÕÉ”€ô•áÁ½ÍÕÉ”ìÍ•±˜¹±•¹Í9…µ”€ô±•¹Í9…µ”ìÍ•±˜¹É…ÝMÕÁÁ½ÉÑ•€ôÉ…ÝMÕÁÁ½ÉÑ•ìÍ•±˜¹‘•Ù¥•MÕµµ…Éä€ô‘•Ù¥•MÕµµ…ÉäìÍÕÁ•È¹¥¹¥Ð¡¹¥‰9…µ”è¹¥°°‰Õ¹‘±”è¹¥°¤ô(€€€É•ÅÕ¥É•¥¹¥Ðü¡½‘•Èè9M½‘•È¤ì™…Ñ…±ÉÉ½È ¤ô((€€€½Ù•ÉÉ¥‘”™Õ¹ŒÙ¥•Ý¥‘1½… ¤ì(€€€€€€€ÍÕÁ•È¹Ù¥•Ý¥‘1½… ¤ìÙ¥•Ü¹‰…­É½Õ¹‘½±½È€ô€¹ÍåÍÑ•µ	…­É½Õ¹ìÑ¥Ñ±”€ô€‰1%AQ!HƒŠˆp¡±•¹Í9…µ”¤ˆ(€€€€€€€¹…Ù¥…Ñ¥½¹%Ñ•´¹É¥¡Ñ	…É	ÕÑÑ½¹%Ñ•´€ôU%	…É	ÕÑÑ½¹%Ñ•´¡Ñ¥Ñ±”è€‹BOBûFBûBËBøˆ°ÍÑå±”è€¹‘½¹”°Ñ…É•ÐèÍ•±˜°…Ñ¥½¸è€Í•±•Ñ½È¡‘½¹”¤¤(€€€€€€€±•ÐÍÉ½±°€ôU%MÉ½±±Y¥•Ü ¤ìÍÉ½±°¹ÑÉ…¹Í±…Ñ•ÍÕÑ½É•Í¥é¥¹5…Í­%¹Ñ½½¹ÍÑÉ…¥¹ÑÌ€ô™…±Í”ìÙ¥•Ü¹…‘‘MÕ‰Ù¥•Ü¡ÍÉ½±°¤(€€€€€€€ÍÑ…¬¹ÑÉ…¹Í±…Ñ•ÍÕÑ½É•Í¥é¥¹5…Í­%¹Ñ½½¹ÍÑÉ…¥¹ÑÌ€ô™…±Í”ìÍÑ…¬¹…á¥Ì€ô€¹Ù•ÉÑ¥…°ìÍÑ…¬¹ÍÁ…¥¹œ€ô€ÄÐìÍÑ…¬¹¥Í1…å½ÕÑ5…É¥¹ÍI•±…Ñ¥Ù•ÉÉ…¹•µ•¹Ð€ôÑÉÕ”ìÍÑ…¬¹±…å½ÕÑ5…É¥¹Ì€ô€¹¥¹¥Ð¡Ñ½Àè€Äà°±•™Ðè€Äà°‰½ÑÑ½´è€ÌÀ°É¥¡Ðè€Äà¤ìÍÉ½±°¹…‘‘MÕ‰Ù¥•Ü¡ÍÑ…¬¤(€€€€€€€9M1…å½ÕÑ½¹ÍÑÉ…¥¹Ð¹…Ñ¥Ù…Ñ”¡mÍÉ½±°¹±•…‘¥¹¹¡½È¹½¹ÍÑÉ…¥¹Ð¡•ÅÕ…±Q¼èÙ¥•Ü¹±•…‘¥¹¹¡½È¤°ÍÉ½±°¹ÑÉ…¥±¥¹¹¡½È¹½¹ÍÑÉ…¥¹Ð¡•ÅÕ…±Q¼èÙ¥•Ü¹ÑÉ…¥±¥¹¹¡½È¤°ÍÉ½±°¹Ñ½Á¹¡½È¹½¹ÍÑÉ…¥¹Ð¡•ÅÕ…±Q¼èÙ¥•Ü¹Ñ½Á¹¡½È¤°ÍÉ½±°¹‰½ÑÑ½µ¹¡½È¹½¹ÍÑÉ…¥¹Ð¡•ÅÕ…±Q¼èÙ¥•Ü¹‰½ÑÑ½µ¹¡½È¤°ÍÑ…¬¹±•…‘¥¹¹¡½È¹½¹ÍÑÉ…¥¹Ð¡•ÅÕ…±Q¼èÍÉ½±°¹½¹Ñ•¹Ñ1…å½ÕÑÕ¥‘”¹±•…‘¥¹¹¡½È¤°ÍÑ…¬¹ÑÉ…¥±¥¹¹¡½È¹½¹ÍÑÉ…¥¹Ð¡•ÅÕ…±Q¼èÍÉ½±°¹½¹Ñ•¹Ñ1…å½ÕÑÕ¥‘”¹ÑÉ…¥±¥¹¹¡½È¤°ÍÑ…¬¹Ñ½Á¹¡½È¹½¹ÍÑÉ…¥¹Ð¡•ÅÕ…±Q¼èÍÉ½±°¹½¹Ñ•¹Ñ1…å½ÕÑÕ¥‘”¹Ñ½Á¹¡½È¤°ÍÑ…¬¹‰½ÑÑ½µ¹¡½È¹½¹ÍÑÉ…¥¹Ð¡•ÅÕ…±Q¼èÍÉ½±°¹½¹Ñ•¹Ñ1…å½ÕÑÕ¥‘”¹‰½ÑÑ½µ¹¡½È¤°ÍÑ…¬¹Ý¥‘Ñ¡¹¡½È¹½¹ÍÑÉ…¥¹Ð¡•ÅÕ…±Q¼èÍÉ½±°¹™É…µ•1…å½ÕÑÕ¥‘”¹Ý¥‘Ñ¡¹¡½È¥t¤((€€€€€€€±•Ð¥¹™¼€ôU%1…‰•° ¤ì¥¹™¼¹¹Õµ‰•É=™1¥¹•Ì€ô€Àì¥¹™¼¹™½¹Ð€ô€¹ÍåÍÑ•µ½¹Ð¡½™M¥é”è€ÄÌ¤ì¥¹™¼¹Ñ•áÑ½±½È€ô€¹Í•½¹‘…Éå1…‰•°ì¥¹™¼¹Ñ•áÐ€ô‘•Ù¥•MÕµµ…ÉäìÍÑ…¬¹…‘‘ÉÉ…¹•‘MÕ‰Ù¥•Ü¡¥¹™¼¤(€€€€€€€±•Ð½¹™¥I½Ü€ôU%MÑ…­Y¥•Ü ¤ì½¹™¥I½Ü¹…á¥Ì€ô€¹¡½É¥é½¹Ñ…°ì½¹™¥I½Ü¹‘¥ÍÑÉ¥‰ÕÑ¥½¸€ô€¹™¥±±ÅÕ…±±äì½¹™¥I½Ü¹ÍÁ…¥¹œ€ô€ÄÀ(€€€€€€€±•Ð¥µÁ½ÉÑ	ÕÑÑ½¸€ôU%	ÕÑÑ½¸¡ÑåÁ”è€¹ÍåÍÑ•´¤ì¥µÁ½ÉÑ	ÕÑÑ½¸¹Í•ÑQ¥Ñ±” ‹BcBóBÿBûFF)M=8ˆ°™½Èè€¹¹½Éµ…°¤ì¥µÁ½ÉÑ	ÕÑÑ½¸¹…‘‘Q…É•Ð¡Í•±˜°…Ñ¥½¸è€Í•±•Ñ½È¡¥µÁ½ÉÑ½¹™¥œ¤°™½Èè€¹Ñ½Õ¡UÁ%¹Í¥‘”¤(€€€€€€€±•Ð•áÁ½ÉÑ	ÕÑÑ½¸€ôU%	ÕÑÑ½¸¡ÑåÁ”è€¹ÍåÍÑ•´¤ì•áÁ½ÉÑ	ÕÑÑ½¸¹Í•ÑQ¥Ñ±” ‹B·BëFBÿBûFF)M=8ˆ°™½Èè€¹¹½Éµ…°¤ì•áÁ½ÉÑ	ÕÑÑ½¸¹…‘‘Q…É•Ð¡Í•±˜°…Ñ¥½¸è€Í•±•Ñ½È¡•áÁ½ÉÑ½¹™¥œ¤°™½Èè€¹Ñ½Õ¡UÁ%¹Í¥‘”¤(€€€€€€€½¹™¥I½Ü¹…‘‘ÉÉ…¹•‘MÕ‰Ù¥•Ü¡¥µÁ½ÉÑ	ÕÑÑ½¸¤ì½¹™¥I½Ü¹…‘‘ÉÉ…¹•‘MÕ‰Ù¥•Ü¡•áÁ½ÉÑ	ÕÑÑ½¸¤ìÍÑ…¬¹…‘‘ÉÉ…¹•‘MÕ‰Ù¥•Ü¡½¹™¥I½Ü¤(€€€€€€€…‘‘!•…‘•È ‹B{BÇF+B×BÓBãB÷B×B÷BãBÔƒBëBÃBÓFBûBÈˆ¤(€€€€€€€±•Ð™É…µ•Ì€ôU%M•µ•¹Ñ•‘½¹ÑÉ½°¡¥Ñ•µÌèlˆÌˆ°€ˆÔˆ°€ˆàˆ°€ˆÄÈ‰t¤ì™É…µ•Ì¹Í•±•Ñ•‘M•µ•¹Ñ%¹‘•à€ôlÌ°Ô°à°ÄÉt¹™¥ÉÍÑ%¹‘•à¡½˜èÍ•ÑÑ¥¹Ì¹™É…µ•½Õ¹Ð¤€üü€Äì™É…µ•Ì¹…‘‘Ñ¥½¸¡U%Ñ¥½¸ìmÝ•…¬Í•±™t|¥¸Í•±˜ü¹Í•ÑÑ¥¹Ì¹™É…µ•½Õ¹Ð€ôlÌ°Ô°à°ÄÉum™É…µ•Ì¹Í•±•Ñ•‘M•µ•¹Ñ%¹‘•átô°™½Èè€¹Ù…±Õ•¡…¹•¤ìÍÑ…¬¹…‘‘ÉÉ…¹•‘MÕ‰Ù¥•Ü¡™É…µ•Ì¤(€€€€€€€…‘‘M±¥‘•È ‹B‡BãBïBÀ!Hˆ°€À°€Ä°Í•ÑÑ¥¹Ì¹¡‘ÉMÑÉ•¹Ñ ¤ìÍ•±˜¹Í•ÑÑ¥¹Ì¹¡‘ÉMÑÉ•¹Ñ €ô€Àô(€€€€€€€…‘‘M±¥‘•È ‹BGBÃBßBûBËBÃF<ƒF7BëFBÿBûBßBãFBãF<ˆ°€´È°€È°•áÁ½ÍÕÉ”°Ù…±Õ•Q•áÐèìMÑÉ¥¹œ¡™½Éµ…Ðè€ˆ”¬¸É˜Xˆ°€À¤ô¤ìÍ•±˜¹•áÁ½ÍÕÉ”€ô€Àô(€€€€€€€…‘‘M±¥‘•È ‹B£FBóBûBÿBûBÓBÃBËBïB×B÷BãBÔˆ°€À°€Ä°Í•ÑÑ¥¹Ì¹‘•¹½¥Í”¤ìÍ•±˜¹Í•ÑÑ¥¹Ì¹‘•¹½¥Í”€ô€Àô(€€€€€€€…‘‘M±¥‘•È ‹BƒB×BßBëBûFFF0ˆ°€À°€Ä°Í•ÑÑ¥¹Ì¹Í¡…ÉÁ¹•ÍÌ¤ìÍ•±˜¹Í•ÑÑ¥¹Ì¹Í¡…ÉÁ¹•ÍÌ€ô€Àô(€€€€€€€…‘‘M±¥‘•È ‹BwBÃFF/F'B×B÷B÷BûFFF0ˆ°€À¸Ü°€Ä¸Ð°Í•ÑÑ¥¹Ì¹Í…ÑÕÉ…Ñ¥½¸¤ìÍ•±˜¹Í•ÑÑ¥¹Ì¹Í…ÑÕÉ…Ñ¥½¸€ô€Àô(€€€€€€€…‘‘M±¥‘•È ‹B‡BËB×FBïF/BÔƒFFBÃFFBëBàˆ°€À°€Ä°Í•ÑÑ¥¹Ì¹¡¥¡±¥¡ÑÌ¤ìÍ•±˜¹Í•ÑÑ¥¹Ì¹¡¥¡±¥¡ÑÌ€ô€Àô(€€€€€€€…‘‘M±¥‘•È ‹BSB×FBÃBïBãBßBÃFBãF<ƒFB×B÷B×Bäˆ°€À°€Ä°Í•ÑÑ¥¹Ì¹Í¡…‘½ÝÌ¤ìÍ•±˜¹Í•ÑÑ¥¹Ì¹Í¡…‘½ÝÌ€ô€Àô(€€€€€€€…‘‘M±¥‘•È ‹B‹B×BóBÿB×FBÃFFFBÀˆ°€ÌÔÀÀ°€àÔÀÀ°Í•ÑÑ¥¹Ì¹Ñ•µÁ•É…ÑÕÉ”°Ù…±Õ•Q•áÐèì€‰p¡%¹Ð À¤¤,ˆô¤ìÍ•±˜¹Í•ÑÑ¥¹Ì¹Ñ•µÁ•É…ÑÕÉ”€ô€Àô(€€€€€€€…‘‘MÝ¥Ñ  ‹B‡BûFFBÃB÷F?FF0ƒB÷B×BÇBøƒBàƒF?FBëBãBÔƒBïBÃBóBÿF,ˆ°Í•ÑÑ¥¹Ì¹ÁÉ•Í•ÉÙ•M­ä¤ìÍ•±˜¹Í•ÑÑ¥¹Ì¹ÁÉ•Í•ÉÙ•M­ä€ô€Àô(€€€€€€€…‘‘MÝ¥Ñ  ‹BwBÃFFFBÃBïF3B÷F/BäƒBûFFB×B÷BûBèƒBëBûBÛBàˆ°Í•ÑÑ¥¹Ì¹¹…ÑÕÉ…±M­¥¸¤ìÍ•±˜¹Í•ÑÑ¥¹Ì¹¹…ÑÕÉ…±M­¥¸€ô€Àô(€€€€€€€…‘‘MÝ¥Ñ  ‹B‡BûFFBÃB÷F?FF0ƒBãFFBûBÓB÷F/BäƒBëBÃBÓF ˆ°Í•ÑÑ¥¹Ì¹Í…Ù•=É¥¥¹…°¤ìÍ•±˜¹Í•ÑÑ¥¹Ì¹Í…Ù•=É¥¥¹…°€ô€Àô(€€€€€€€…‘‘MÝ¥Ñ ¡É…ÝMÕÁÁ½ÉÑ•€ü€‰I\½AÉ½I\ˆ€è€‰I\½AÉ½I\ƒŠPƒB÷BÔƒBÿBûBÓBÓB×FBÛBãBËBÃB×FFF<ˆ°Í•ÑÑ¥¹Ì¹É…Ý¹…‰±•€˜˜É…ÝMÕÁÁ½ÉÑ•°•¹…‰±•èÉ…ÝMÕÁÁ½ÉÑ•¤ìÍ•±˜¹Í•ÑÑ¥¹Ì¹É…Ý¹…‰±•€ô€Àô((€€€€€€€…‘‘!•…‘•È ‹B›BËB×FBûBËBûBäƒBÿFBûFBãBïF0ˆ¤(€€€€€€€±•ÐÍÑå±•Ì€ôU%M•µ•¹Ñ•‘½¹ÑÉ½°¡¥Ñ•µÌèl‹BSB×B÷F0ˆ°€‹BwBûFF0ˆ°€‹BoF;BÓBàˆ°€‹BFBãFBûBÓBÀ‰t¤ìÍÑå±•Ì¹Í•±•Ñ•‘M•µ•¹Ñ%¹‘•à€ôÍ•ÑÑ¥¹Ì¹ÍÑå±”ìÍÑå±•Ì¹…‘‘Ñ¥½¸¡U%Ñ¥½¸ìmÝ•…¬Í•±™t|¥¸Í•±˜ü¹Í•ÑÑ¥¹Ì¹ÍÑå±”€ôÍÑå±•Ì¹Í•±•Ñ•‘M•µ•¹Ñ%¹‘•àô°™½Èè€¹Ù…±Õ•¡…¹•¤ìÍÑ…¬¹…‘‘ÉÉ…¹•‘MÕ‰Ù¥•Ü¡ÍÑå±•Ì¤((€€€€€€€…‘‘!•…‘•È ‹BƒFFB÷BûBÔƒFBÿFBÃBËBïB×B÷BãBÔˆ¤(€€€€€€€…‘‘MÝ¥Ñ  ‹BKBëBïF;FBãFF0AÉ¼·FB×BÛBãBðˆ°Í•ÑÑ¥¹Ì¹µ…¹Õ…±¹…‰±•¤ìÍ•±˜¹Í•ÑÑ¥¹Ì¹µ…¹Õ…±¹…‰±•€ô€Àô(€€€€€€€…‘‘M±¥‘•È ‰%M<ˆ°€ÈÔ°€ÌÈÀÀ°Í•ÑÑ¥¹Ì¹¥Í¼°Ù…±Õ•Q•áÐèì€‰p¡%¹Ð À¤¤ˆô¤ìÍ•±˜¹Í•ÑÑ¥¹Ì¹¥Í¼€ô€Àô(€€€€€€€…‘‘M±¥‘•È ‹BKF/BÓB×FBÛBëBÀˆ°€Ä¸À¼àÀÀÀ¸À°€Ä°Í•ÑÑ¥¹Ì¹Í¡ÕÑÑ•ÉM•½¹‘Ì°Ù…±Õ•Q•áÐèì€À€øô€À¸Ô€üMÑÉ¥¹œ¡™½Éµ…Ðè€ˆ”¸Å˜ƒFˆ°€À¤€è€ˆÄ½p¡µ…à Ä°%¹Ð Ä€¼€À¤¤¤ƒFˆô¤ìÍ•±˜¹Í•ÑÑ¥¹Ì¹Í¡ÕÑÑ•ÉM•½¹‘Ì€ô€Àô(€€€€€€€…‘‘M±¥‘•È ‹BƒFFB÷BûBäƒFBûBëFFˆ°€À°€Ä°Í•ÑÑ¥¹Ì¹™½ÕÌ¤ìÍ•±˜¹Í•ÑÑ¥¹Ì¹™½ÕÌ€ô€Àô(€€€€€€€…‘‘M±¥‘•È ‹BGBÃBïBÃB÷FƒBÇB×BïBûBÏBøˆ°€ÌÀÀÀ°€àÔÀÀ°Í•ÑÑ¥¹Ì¹Ý¡¥Ñ•	…±…¹”°Ù…±Õ•Q•áÐèì€‰p¡%¹Ð À¤¤,ˆô¤ìÍ•±˜¹Í•ÑÑ¥¹Ì¹Ý¡¥Ñ•	…±…¹”€ô€Àô(€€€ô((€€€ÁÉ¥Ù…Ñ”™Õ¹Œ…‘‘!•…‘•È¡|Ñ•áÐèMÑÉ¥¹œ¤ì±•Ð±…‰•°€ôU%1…‰•° ¤ì±…‰•°¹Ñ•áÐ€ôÑ•áÐì±…‰•°¹™½¹Ð€ô€¹ÍåÍÑ•µ½¹Ð¡½™M¥é”è€Äà°Ý•¥¡Ðè€¹‰½±¤ì±…‰•°¹Ñ•áÑ½±½È€ô€¹±…‰•°ìÍÑ…¬¹…‘‘ÉÉ…¹•‘MÕ‰Ù¥•Ü¡±…‰•°¤ô((€€€ÁÉ¥Ù…Ñ”™Õ¹Œ…‘‘MÝ¥Ñ ¡|Ñ¥Ñ±”èMÑÉ¥¹œ°|Ù…±Õ”è	½½°°•¹…‰±•è	½½°€ôÑÉÕ”°¡…¹”è•Í…Á¥¹œ€¡	½½°¤€´øY½¥¤ì(€€€€€€€±•ÐÉ½Ü€ôU%MÑ…­Y¥•Ü ¤ìÉ½Ü¹…á¥Ì€ô€¹¡½É¥é½¹Ñ…°(€€€€€€€±•Ð±…‰•°€ôU%1…‰•° ¤ì±…‰•°¹Ñ•áÐ€ôÑ¥Ñ±”ì±…‰•°¹™½¹Ð€ô€¹ÍåÍÑ•µ½¹Ð¡½™M¥é”è€ÄÔ¤ì±…‰•°¹¹Õµ‰•É=™1¥¹•Ì€ô€È(€€€€€€€±•Ð½¹ÑÉ½°€ôU%MÝ¥Ñ  ¤ì½¹ÑÉ½°¹¥Í=¸€ôÙ…±Õ”ì½¹ÑÉ½°¹¥Í¹…‰±•€ô•¹…‰±•ì½¹ÑÉ½°¹…‘‘Ñ¥½¸¡U%Ñ¥½¸ì|¥¸¡…¹”¡½¹ÑÉ½°¹¥Í=¸¤ô°™½Èè€¹Ù…±Õ•¡…¹•¤(€€€€€€€É½Ü¹…‘‘ÉÉ…¹•‘MÕ‰Ù¥•Ü¡±…‰•°¤ìÉ½Ü¹…‘‘ÉÉ…¹•‘MÕ‰Ù¥•Ü¡½¹ÑÉ½°¤ìÍÑ…¬¹…‘‘ÉÉ…¹•‘MÕ‰Ù¥•Ü¡É½Ü¤(€€€ô((€€€ÁÉ¥Ù…Ñ”™Õ¹Œ…‘‘M±¥‘•È¡|Ñ¥Ñ±”èMÑÉ¥¹œ°|µ¥¸è±½…Ð°|µ…àè±½…Ð°|Ù…±Õ”è±½…Ð°Ù…±Õ•Q•áÐè•Í…Á¥¹œ€¡±½…Ð¤€´øMÑÉ¥¹œ€ôìMÑÉ¥¹œ¡™½Éµ…Ðè€ˆ”¸É˜ˆ°€À¤ô°¡…¹”è•Í…Á¥¹œ€¡±½…Ð¤€´øY½¥¤ì(€€€€€€€±•Ð±…‰•°€ôU%1…‰•° ¤ì±…‰•°¹™½¹Ð€ô€¹ÍåÍÑ•µ½¹Ð¡½™M¥é”è€ÄÐ°Ý•¥¡Ðè€¹µ•‘¥Õ´¤ì±…‰•°¹Ñ•áÐ€ô€‰p¡Ñ¥Ñ±”¤èp¡Ù…±Õ•Q•áÐ¡Ù…±Õ”¤¤ˆìÍÑ…¬¹…‘‘ÉÉ…¹•‘MÕ‰Ù¥•Ü¡±…‰•°¤(€€€€€€€±•ÐÍ±¥‘•È€ôU%M±¥‘•È ¤ìÍ±¥‘•È¹µ¥¹¥µÕµY…±Õ”€ôµ¥¸ìÍ±¥‘•È¹µ…á¥µÕµY…±Õ”€ôµ…àìÍ±¥‘•È¹Ù…±Õ”€ôÙ…±Õ”ìÍ±¥‘•È¹µ¥¹¥µÕµQÉ…­Q¥¹Ñ½±½È€ôU%½±½È¡É•è€À¸äÔ°É••¸è€À¸ØÈ°‰±Õ”è€À¸Àà°…±Á¡„è€Ä¤(€€€€€€€Í±¥‘•È¹…‘‘Ñ¥½¸¡U%Ñ¥½¸ì|¥¸±…‰•°¹Ñ•áÐ€ô€‰p¡Ñ¥Ñ±”¤èp¡Ù…±Õ•Q•áÐ¡Í±¥‘•È¹Ù…±Õ”¤¤ˆì¡…¹”¡Í±¥‘•È¹Ù…±Õ”¤ô°™½Èè€¹Ù…±Õ•¡…¹•¤ìÍÑ…¬¹…‘‘ÉÉ…¹•‘MÕ‰Ù¥•Ü¡Í±¥‘•È¤(€€€ô((€€€½‰©ŒÁÉ¥Ù…Ñ”™Õ¹Œ¥µÁ½ÉÑ½¹™¥œ ¤ì(€€€€€€€±•ÐÁ¥­•È€ôU%½Õµ•¹ÑA¥­•ÉY¥•Ý½¹ÑÉ½±±•È¡™½É=Á•¹¥¹½¹Ñ•¹ÑQåÁ•Ìèl¹©Í½¹t°…Í½ÁäèÑÉÕ”¤ìÁ¥­•È¹‘•±•…Ñ”€ôÍ•±˜ìÁÉ•Í•¹Ð¡Á¥­•È°…¹¥µ…Ñ•èÑÉÕ”¤(€€€ô((€€€½‰©ŒÁÉ¥Ù…Ñ”™Õ¹Œ•áÁ½ÉÑ½¹™¥œ ¤ì(€€€€€€€±•Ð½¹™¥œ€ôQ¥É½¹™¥œ¡Í•ÑÑ¥¹ÌèÍ•ÑÑ¥¹Ì°•áÁ½ÍÕÉ”è•áÁ½ÍÕÉ”°¹…µ”è€‰Q¥ÈMÑå±”p¡±•¹Í9…µ”¤ˆ¤(€€€€€€€±•Ð•¹½‘•È€ô)M=9¹½‘•È ¤ì•¹½‘•È¹½ÕÑÁÕÑ½Éµ…ÑÑ¥¹œ€ôl¹ÁÉ•ÑÑåAÉ¥¹Ñ•°€¹Í½ÉÑ•‘-•åÍt(€€€€€€€Õ…É±•Ð‘…Ñ„€ôÑÉäü•¹½‘•È¹•¹½‘”¡½¹™¥œ¤•±Í”ìÉ•ÑÕÉ¸ô(€€€€€€€±•ÐÕÉ°€ô¥±•5…¹…•È¹‘•™…Õ±Ð¹Ñ•µÁ½É…Éå¥É•Ñ½Éä¹…ÁÁ•¹‘¥¹A…Ñ¡½µÁ½¹•¹Ð ‰Q¥ÈµMÑå±”µp¡±•¹Í9…µ”¤¹©Í½¸ˆ¤(€€€€€€€‘¼ìÑÉä‘…Ñ„¹ÝÉ¥Ñ”¡Ñ¼èÕÉ°°½ÁÑ¥½¹Ìè€¹…Ñ½µ¥Œ¤ìÁÉ•Í•¹Ð¡U%Ñ¥Ù¥ÑåY¥•Ý½¹ÑÉ½±±•È¡…Ñ¥Ù¥Ñå%Ñ•µÌèmÕÉ±t°…ÁÁ±¥…Ñ¥½¹Ñ¥Ù¥Ñ¥•Ìè¹¥°¤°…¹¥µ…Ñ•èÑÉÕ”¤ô…Ñ ìô(€€€ô((€€€™Õ¹Œ‘½Õµ•¹ÑA¥­•È¡|½¹ÑÉ½±±•ÈèU%½Õµ•¹ÑA¥­•ÉY¥•Ý½¹ÑÉ½±±•È°‘¥‘A¥­½Õµ•¹ÑÍÐÕÉ±ÌèmUI1t¤ì(€€€€€€€Õ…É±•ÐÕÉ°€ôÕÉ±Ì¹™¥ÉÍÐ°±•Ð‘…Ñ„€ôÑÉäü…Ñ„¡½¹Ñ•¹ÑÍ=˜èÕÉ°¤°±•Ð½¹™¥œ€ôÑÉäü)M=9•½‘•È ¤¹‘•½‘”¡Q¥É½¹™¥œ¹Í•±˜°™É½´è‘…Ñ„¤•±Í”ì(€€€€€€€€€€€±•Ð…±•ÉÐ€ôU%±•ÉÑ½¹ÑÉ½±±•È¡Ñ¥Ñ±”è€‹B{F#BãBÇBëBÀˆ°µ•ÍÍ…”è€‹BwBÔƒFBÓBÃBïBûFF0ƒBÿFBûFBãFBÃFF0ƒBëBûB÷FBãBÌQ¥È)M=8¸ˆ°ÁÉ•™•ÉÉ•‘MÑå±”è€¹…±•ÉÐ¤ì…±•ÉÐ¹…‘‘Ñ¥½¸¡U%±•ÉÑÑ¥½¸¡Ñ¥Ñ±”è€‰=,ˆ°ÍÑå±”è€¹‘•™…Õ±Ð¤¤ìÁÉ•Í•¹Ð¡…±•ÉÐ°…¹¥µ…Ñ•èÑÉÕ”¤ìÉ•ÑÕÉ¸(€€€€€€€ô(€€€€€€€Í•ÑÑ¥¹Ì€ô½¹™¥œ¹…ÁÁ±¥•¡Ñ¼èÍ•ÑÑ¥¹Ì¤ì•áÁ½ÍÕÉ”€ôµ¥¸¡µ…à¡½¹™¥œ¹•áÁ½ÍÕÉ”°€´È¤°€È¤(€€€€€€€±•Ð…±•ÉÐ€ôU%±•ÉÑ½¹ÑÉ½±±•È¡Ñ¥Ñ±”è€‹BkBûB÷FBãBÌƒBãBóBÿBûFFBãFBûBËBÃBôˆ°µ•ÍÍ…”è€‰p¡½¹™¥œ¹¹…µ”¤ƒBÿFBãBóB×B÷FGBôƒBèƒBûBÇF+B×BëFBãBËFp¡±•¹Í9…µ”¤¸ˆ°ÁÉ•™•ÉÉ•‘MÑå±”è€¹…±•ÉÐ¤(€€€€€€€…±•ÉÐ¹…‘‘Ñ¥½¸¡U%±•ÉÑÑ¥½¸¡Ñ¥Ñ±”è€‹BFBãBóB×B÷BãFF0ˆ°ÍÑå±”è€¹‘•™…Õ±Ð¤ìmÝ•…¬Í•±™t|¥¸Õ…É±•ÐÍ•±˜•±Í”ìÉ•ÑÕÉ¸ôìÍ•±˜¹½¹M…Ù”ü¡Í•±˜¹Í•ÑÑ¥¹Ì°Í•±˜¹•áÁ½ÍÕÉ”¤ìÍ•±˜¹‘¥Íµ¥ÍÌ¡…¹¥µ…Ñ•èÑÉÕ”¤ô¤(€€€€€€€ÁÉ•Í•¹Ð¡…±•ÉÐ°…¹¥µ…Ñ•èÑÉÕ”¤(€€€ô((€€€½‰©ŒÁÉ¥Ù…Ñ”™Õ¹Œ‘½¹” ¤ì½¹M…Ù”ü¡Í•ÑÑ¥¹Ì°•áÁ½ÍÕÉ”¤ì‘¥Íµ¥ÍÌ¡…¹¥µ…Ñ•èÑÉÕ”¤ô)ô()ÁÉ¥Ù…Ñ”•¹Õ´•Ù¥•%¹™¼ì(€€€ÍÑ…Ñ¥Œ™Õ¹Œµ…¡¥¹” ¤€´øMÑÉ¥¹œìÙ…È¥¹™¼€ôÕÑÍ¹…µ” ¤ìÕ¹…µ” ™¥¹™¼¤ìÉ•ÑÕÉ¸Ý¥Ñ¡U¹Í…™•A½¥¹Ñ•È¡Ñ¼è€™¥¹™¼¹µ…¡¥¹”¤ì€À¹Ý¥Ñ¡5•µ½ÉåI•‰½Õ¹¡Ñ¼è¡…È¹Í•±˜°…Á…¥Ñäè€Ä¤ìMÑÉ¥¹œ¡MÑÉ¥¹œè€À¤ôôô(€€€ÍÑ…Ñ¥Œ™Õ¹Œ¡…Í1•¹Ì¡|ÑåÁ”èY…ÁÑÕÉ••Ù¥”¹•Ù¥•QåÁ”¤€´ø	½½°ì€…Y…ÁÑÕÉ••Ù¥”¹¥Í½Ù•ÉåM•ÍÍ¥½¸¡‘•Ù¥•QåÁ•ÌèmÑåÁ•t°µ•‘¥…QåÁ”è€¹Ù¥‘•¼°Á½Í¥Ñ¥½¸è€¹‰…¬¤¹‘•Ù¥•Ì¹¥ÍµÁÑäô(€€€ÍÑ…Ñ¥Œ™Õ¹ŒÍ¡½ÉÑMÕµµ…Éä¡Á¡½Ñ½=ÕÑÁÕÐèY…ÁÑÕÉ•A¡½Ñ½=ÕÑÁÕÐ¤€´øMÑÉ¥¹œì€‰p¡µ…¡¥¹” ¤¤ƒŠˆI\p¡Á¡½Ñ½=ÕÑÁÕÐ¹…Ù…¥±…‰±•I…ÝA¡½Ñ½A¥á•±½Éµ…ÑQåÁ•Ì¹¥ÍµÁÑä€ü€‹B÷B×Fˆ€è€‹BÓBÀˆ¤ˆô(€€€ÍÑ…Ñ¥Œ™Õ¹ŒÍÕµµ…Éä¡Á¡½Ñ½=ÕÑÁÕÐèY…ÁÑÕÉ•A¡½Ñ½=ÕÑÁÕÐ¤€´øMÑÉ¥¹œì(€€€€€€€€‹BFFFBûBçFFBËBøèp¡µ…¡¥¹” ¤¥q¸À¸×\èp¡¡…Í1•¹Ì ¹‰Õ¥±Ñ%¹U±ÑÉ…]¥‘•…µ•É„¤€ü€‹BÿBûBÓBÓB×FBÛBãBËBÃB×FFF<ˆ€è€‹B÷B×Fˆ¤ƒŠˆ€Ë\èp¡¡…Í1•¹Ì ¹‰Õ¥±Ñ%¹Q•±•Á¡½Ñ½…µ•É„¤€ü€‹BÿBûBÓBÓB×FBÛBãBËBÃB×FFF<ˆ€è€‹B÷B×Fˆ¥q¹I\½AÉ½I\èp¡Á¡½Ñ½=ÕÑÁÕÐ¹…Ù…¥±…‰±•I…ÝA¡½Ñ½A¥á•±½Éµ…ÑQåÁ•Ì¹¥ÍµÁÑä€ü€‹B÷BÔƒBÿBûBÓBÓB×FBÛBãBËBÃB×FFF<ˆ€è€‹BÿBûBÓBÓB×FBÛBãBËBÃB×FFF<ˆ¤ƒŠˆƒBBûFFFB×FB÷BÃF<ƒBÏBïFBÇBãB÷BÀèp¡Á¡½Ñ½=ÕÑÁÕÐ¹¥Í•ÁÑ¡…Ñ…•±¥Ù•ÉåMÕÁÁ½ÉÑ•€ü€‹BÓBÀˆ€è€‹BÿFBûBÏFBÃBóBóB÷BûBÔƒFBÃBßBóF/FBãBÔˆ¤ˆ(€€€ô)ô()•áÑ•¹Í¥½¸…µ•É…Y¥•Ý½¹ÑÉ½±±•ÈèY…ÁÑÕÉ•¥±•=ÕÑÁÕÑI•½É‘¥¹•±•…Ñ”ì(€€€™Õ¹Œ™¥±•=ÕÑÁÕÐ¡|½ÕÑÁÕÐèY…ÁÑÕÉ•¥±•=ÕÑÁÕÐ°‘¥‘¥¹¥Í¡I•½É‘¥¹Q¼½ÕÑÁÕÑ¥±•UI0èUI0°™É½´½¹¹•Ñ¥½¹ÌèmY…ÁÑÕÉ•½¹¹•Ñ¥½¹t°•ÉÉ½ÈèÉÉ½Èü¤ì(€€€€€€€¥ÍÁ…Ñ¡EÕ•Õ”¹µ…¥¸¹…Íå¹ŒìÍ•±˜¹Í•ÑI•½É‘¥¹U$¡…Ñ¥Ù”è™…±Í”¤ô(€€€€€€€Õ…É•ÉÉ½È€ôô¹¥°•±Í”ìÑÉäü¥±•5…¹…•È¹‘•™…Õ±Ð¹É•µ½Ù•%Ñ•´¡…Ðè½ÕÑÁÕÑ¥±•UI0¤ì¥ÍÁ…Ñ¡EÕ•Õ”¹µ…¥¸¹…Íå¹ŒìÍ•±˜¹Í¡½ÝMÑ…ÑÕÌ ‹B{F#BãBÇBëBÀƒBßBÃBÿBãFBàˆ¤ôìÉ•ÑÕÉ¸ô(€€€€€€€Í…Ù•Y¥‘•¼¡½ÕÑÁÕÑ¥±•UI0¤(€€€ô)ô()•áÑ•¹Í¥½¸…µ•É…Y¥•Ý½¹ÑÉ½±±•ÈèA!A¥­•ÉY¥•Ý½¹ÑÉ½±±•É•±•…Ñ”ì™Õ¹ŒÁ¥­•È¡|Á¥­•ÈèA!A¥­•ÉY¥•Ý½¹ÑÉ½±±•È°‘¥‘¥¹¥Í¡A¥­¥¹œÉ•ÍÕ±ÑÌèmA!A¥­•ÉI•ÍÕ±Ñt¤ìÁ¥­•È¹‘¥Íµ¥ÍÌ¡…¹¥µ…Ñ•èÑÉÕ”¤ôô()ÁÉ¥Ù…Ñ”™¥¹…°±…ÍÌÉ¥‘=Ù•É±…åY¥•ÜèU%Y¥•Üì(€€€½Ù•ÉÉ¥‘”±…ÍÌÙ…È±…å•É±…ÍÌè¹å±…ÍÌìM¡…Á•1…å•È¹Í•±˜ô(€€€½Ù•ÉÉ¥‘”™Õ¹Œ±…å½ÕÑMÕ‰Ù¥•ÝÌ ¤ì(€€€€€€€ÍÕÁ•È¹±…å½ÕÑMÕ‰Ù¥•ÝÌ ¤ìÕ…É±•ÐÍ¡…Á”€ô±…å•È…ÌüM¡…Á•1…å•È•±Í”ìÉ•ÑÕÉ¸ôì±•ÐÁ…Ñ €ôU%	•é¥•ÉA…Ñ  ¤(€€€€€€€™½È˜¥¸m±½…Ð Ä¸À¼Ì¸À¤°±½…Ð È¸À¼Ì¸À¥tìÁ…Ñ ¹µ½Ù”¡Ñ¼è€¹¥¹¥Ð¡àè‰½Õ¹‘Ì¹Ý¥‘Ñ ©˜°äè€À¤¤ìÁ…Ñ ¹…‘‘1¥¹”¡Ñ¼è€¹¥¹¥Ð¡àè‰½Õ¹‘Ì¹Ý¥‘Ñ ©˜°äè‰½Õ¹‘Ì¹¡•¥¡Ð¤¤ìÁ…Ñ ¹µ½Ù”¡Ñ¼è€¹¥¹¥Ð¡àè€À°äè‰½Õ¹‘Ì¹¡•¥¡Ð©˜¤¤ìÁ…Ñ ¹…‘‘1¥¹”¡Ñ¼è€¹¥¹¥Ð¡àè‰½Õ¹‘Ì¹Ý¥‘Ñ °äè‰½Õ¹‘Ì¹¡•¥¡Ð©˜¤¤ô(€€€€€€€Í¡…Á”¹Á…Ñ €ôÁ…Ñ ¹A…Ñ ìÍ¡…Á”¹ÍÑÉ½­•½±½È€ôU%½±½È¹Ý¡¥Ñ”¹Ý¥Ñ¡±Á¡…½µÁ½¹•¹Ð À¸ÌÐ¤¹½±½ÈìÍ¡…Á”¹™¥±±½±½È€ôU%½±½È¹±•…È¹½±½ÈìÍ¡…Á”¹±¥¹•]¥‘Ñ €ô€À¸Ü(€€€ô)ô(
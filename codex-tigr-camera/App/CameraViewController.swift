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
        case .normal: return "Обычный"
        case .hdr: return "HDR+"
        case .night: return "Ночь"
        case .portrait: return "Портрет"
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
        for (title, tag) in [("0.5×", 5), ("1×", 10), ("2×", 20)] {
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
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor), topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.topAnchor.constraint(equalTo: view.topAnchor), topBar.heightAnchor.constraint(equalToConstant: 82),
            topStack.leadingAnchor.constraint(equalTo: topBar.contentView.leadingAnchor, constant: 16),
            topStack.trailingAnchor.constraint(equalTo: topBar.contentView.trailingAnchor, constant: -16),
            topStack.bottomAnchor.constraint(equalTo: topBar.contentView.bottomAnchor, constant: -8), topStack.heightAnchor.constraint(equalToConstant: 42),
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor), bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor), bottomBar.heightAnchor.constraint(equalToConstant: 235),
            modeControl.topAnchor.constraint(equalTo: bottomBar.contentView.topAnchor, constant: 14), modeControl.centerXAnchor.constraint(equalTo: bottomBar.contentView.centerXAnchor),
            modeControl.widthAnchor.constraint(equalTo: bottomBar.contentView.widthAnchor, constant: -28),
            exposureLabel.leadingAnchor.constraint(equalTo: bottomBar.contentView.leadingAnchor, constant: 24), exposureLabel.topAnchor.constraint(equalTo: modeControl.bottomAnchor, constant: 14), exposureLabel.widthAnchor.constraint(equalToConstant: 52),
            exposureSlider.leadingAnchor.constraint(equalTo: exposureLabel.trailingAnchor, constant: 8), exposureSlider.trailingAnchor.constraint(equalTo: bottomBar.contentView.trailingAnchor, constant: -24), exposureSlider.centerYAnchor.constraint(equalTo: exposureLabel.centerYAnchor),
            shutterButton.centerXAnchor.constraint(equalTo: bottomBar.contentView.centerXAnchor), shutterButton.bottomAnchor.constraint(equalTo: bottomBar.contentView.safeAreaLayoutGuide.bottomAnchor, constant: -20), shutterButton.widthAnchor.constraint(equalToConstant: 72), shutterButton.heightAnchor.constraint(equalToConstant: 72),
            galleryButton.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor), galleryButton.trailingAnchor.constraint(equalTo: shutterButton.leadingAnchor, constant: -54), galleryButton.widthAnchor.constraint(equalToConstant: 54), galleryButton.heightAnchor.constraint(equalToConstant: 54),
            switchButton.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor), switchButton.leadingAnchor.constraint(equalTo: shutterButton.trailingAnchor, constant: 54), switchButton.widthAnchor.constraint(equalToConstant: 54), switchButton.heightAnchor.constraint(equalToConstant: 54),
            zoomStack.centerXAnchor.constraint(equalTo: view.centerXAnchor), zoomStack.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -14), zoomStack.widthAnchor.constraint(equalToConstant: 190), zoomStack.heightAnchor.constraint(equalToConstant: 36),
            countdownLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor), countdownLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            recordingLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor), recordingLabel.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 12), recordingLabel.widthAnchor.constraint(equalToConstant: 112), recordingLabel.heightAnchor.constraint(equalToConstant: 28),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor), statusLabel.bottomAnchor.constraint(equalTo: zoomStack.topAnchor, constant: -16), statusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 170), statusLabel.heightAnchor.constraint(equalToConstant: 34)
        ])
    }

    private func configureTopButton(_ button: UIButton, image: String, action: Selector) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: image), for: .normal)
        button.tintColor = .white
        button.addTarget(self, action: action, for: .touchUpInside)
        button.widthAnchor.constraint(equalToConstant: 42).isActive = true
    }

    private func configureRoundButton(_ button: UIButton, image: String, action: Selector) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: image), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        button.layer.cornerRadius = 27
        button.addTarget(self, action: action, for: .touchUpInside)
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
                if self.photoOutput.isDepthDataDeliverySupported { self.photoOutput.isDepthDataDeliveryEnabled = true }
                if self.photoOutput.isAppleProRAWSupported { self.photoOutput.isAppleProRAWEnabled = true }
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
                if self.session.canAddInput(newInput) { self.session.addInput(newInput); self.videoInput = newInput }
                else if let oldInput, self.session.canAddInput(oldInput) { self.session.addInput(oldInput) }
                self.session.commitConfiguration()
                self.applyManualControls()
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

    @objc private func toggleFlash() {
        flashMode = flashMode == .off ? .on : (flashMode == .on ? .auto : .off)
        let symbol = flashMode == .on ? "bolt.fill" : (flashMode == .auto ? "bolt.badge.a.fill" : "bolt.slash.fill")
        flashButton.setImage(UIImage(systemName: symbol), for: .normal)
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
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration(); self.session.sessionPreset = self.isVideoMode ? .high : .photo; self.session.commitConfiguration()
        }
        showStatus(isVideoMode ? "Режим видео" : photoMode.title)
    }

    @objc private func modeChanged() {
        photoMode = PhotoMode(rawValue: modeControl.selectedSegmentIndex) ?? .normal
        isVideoMode = false; videoButton.tintColor = .white; shutterButton.backgroundColor = .white
        showStatus(photoMode.title)
    }

    @objc private func exposureChanged() {
        let value = exposureSlider.value
        exposureLabel.text = String(format: "EV %.1f", value)
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
        let count: Int
        switch photoMode { case .normal, .portrait: count = 1; case .hdr, .night: count = settings.frameCount }
        guard count > 1 else { return [exposureSlider.value] }
        let range: Float = photoMode == .night ? 1.35 : 1.7
        let step = (range * 2.0) / Float(count - 1)
        let base = exposureSlider.value - range
        var values: [Float] = []
        for index in 0..<count { values.append(base + step * Float(index)) }
        return values
    }

    private func captureSeries() {
        guard !isCapturingSeries else { return }
        isCapturingSeries = true; shutterButton.isEnabled = false
        let brackets = exposureBrackets()
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
            let rawAvailable = self.settings.rawEnabled && wantsRaw && !self.photoOutput.availableRawPhotoPixelFormatTypes.isEmpty
            let captureSettings: AVCapturePhotoSettings
            if rawAvailable {
                captureSettings = AVCapturePhotoSettings(rawPixelFormatType: self.photoOutput.availableRawPhotoPixelFormatTypes[0], processedFormat: [AVVideoCodecKey: AVVideoCodecType.hevc])
            } else {
                captureSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            }
            captureSettings.isHighResolutionPhotoEnabled = true
            if self.videoInput?.device.hasFlash == true { captureSettings.flashMode = self.flashMode }
            if self.photoMode == .portrait && self.photoOutput.isDepthDataDeliverySupported { captureSettings.isDepthDataDeliveryEnabled = true }
            if let connection = self.photoOutput.connection(with: .video) {
                connection.videoOrientation = .portrait
                connection.isVideoMirrored = self.videoInput?.device.position == .front
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
        processingQueue.async { [weak self] in
            let result = PhotoProcessor.process(frames.map(\.image), mode: mode, settings: prefs)
            DispatchQueue.main.async {
                guard let self else { return }
                guard let image = result, let data = image.jpegData(compressionQuality: 0.96) else { self.finishCapture(message: "Ошибка обработки"); return }
                self.galleryButton.setImage(image.withRenderingMode(.alwaysOriginal), for: .normal)
                self.galleryButton.imageView?.contentMode = .scaleAspectFill; self.galleryButton.clipsToBounds = true
                self.saveCapture(processed: data, original: prefs.saveOriginal ? frames.first?.originalData : nil, raw: frames.first?.rawData)
                self.finishCapture(message: "Фото сохранено")
            }
        }
    }

    private func finishCapture(message: String) {
        isCapturingSeries = false; shutterButton.isEnabled = true; showStatus(message)
        if !settings.manualEnabled { exposureChanged() }
    }

    private func prepareVideoRecording() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .notDetermined { AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in DispatchQueue.main.async { self?.startRecording() } } }
        else { startRecording() }
    }

    private func startRecording() {
        sessionQueue.async { [weak self] in
            guard let self, !self.movieOutput.isRecording else { return }
            self.addAudioInputIfAllowed()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("TigrCamera-\(UUID().uuidString).mov")
            if let connection = self.movieOutput.connection(with: .video) { connection.videoOrientation = .portrait; connection.isVideoMirrored = self.videoInput?.device.position == .front }
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
            DispatchQueue.main.async { self.setRecordingUI(active: true) }
        }
    }

    private func addAudioInputIfAllowed() {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized, audioInput == nil, let device = AVCaptureDevice.default(for: .audio), let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration(); if session.canAddInput(input) { session.addInput(input); audioInput = input }; session.commitConfiguration()
    }

    private func stopRecording() { sessionQueue.async { [weak self] in self?.movieOutput.stopRecording() }; setRecordingUI(active: false) }

    private func setRecordingUI(active: Bool) {
        recordingTimer?.invalidate(); recordingStartedAt = active ? Date() : nil; recordingLabel.isHidden = !active
        shutterButton.layer.cornerRadius = active ? 12 : 36; shutterButton.transform = active ? CGAffineTransform(scaleX: 0.62, y: 0.62) : .identity
        if active { recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let start = self?.recordingStartedAt else { return }; let seconds = Int(Date().timeIntervalSince(start)); self?.recordingLabel.text = String(format: " REC %02d:%02d ", seconds / 60, seconds % 60)
        }}
    }

    @objc private func switchCamera() {
        guard !movieOutput.isRecording, !isCapturingSeries else { return }
        settings.save(lens: currentLensKey)
        let goingFront = videoInput?.device.position == .back
        currentLensKey = goingFront ? "front" : "1x"
        settings = ProcessingSettings.load(lens: currentLensKey)
        replaceVideoInput(position: goingFront ? .front : .back, lens: .builtInWideAngleCamera)
    }

    @objc private func zoomPreset(_ sender: UIButton) {
        guard !isCapturingSeries else { return }
        if videoInput?.device.position == .front { applyZoom(sender.tag == 20 ? 2 : 1); return }
        settings.save(lens: currentLensKey)
        currentLensKey = sender.tag == 5 ? "0.5x" : (sender.tag == 20 ? "2x" : "1x")
        settings = ProcessingSettings.load(lens: currentLensKey)
        let lens: AVCaptureDevice.DeviceType = sender.tag == 5 ? .builtInUltraWideCamera : (sender.tag == 20 ? .builtInTelephotoCamera : .builtInWideAngleCamera)
        replaceVideoInput(position: .back, lens: lens)
        zoomStack.arrangedSubviews.compactMap { $0 as? UIButton }.forEach { $0.backgroundColor = $0 == sender ? UIColor(red: 0.98, green: 0.74, blue: 0.18, alpha: 0.8) : UIColor.black.withAlphaComponent(0.55) }
    }

    @objc private func pinchZoom(_ gesture: UIPinchGestureRecognizer) {
        guard let device = videoInput?.device, gesture.state == .changed else { return }; applyZoom(device.videoZoomFactor * gesture.scale); gesture.scale = 1
    }

    private func applyZoom(_ factor: CGFloat) {
        sessionQueue.async { [weak self] in guard let device = self?.videoInput?.device else { return }; do { try device.lockForConfiguration(); device.videoZoomFactor = min(max(factor, 1), min(device.activeFormat.videoMaxZoomFactor, 8)); device.unlockForConfiguration() } catch { } }
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

    @objc private func openSettings() {
        let rawSupported = !photoOutput.availableRawPhotoPixelFormatTypes.isEmpty
        let controller = ProcessingSettingsViewController(settings: settings, exposure: exposureSlider.value, lensName: currentLensKey, rawSupported: rawSupported, deviceSummary: DeviceInfo.summary(photoOutput: photoOutput))
        controller.onSave = { [weak self] newSettings, exposure in
            guard let self else { return }; self.settings = newSettings; newSettings.save(lens: self.currentLensKey)
            self.exposureSlider.value = exposure; self.exposureChanged(); self.sessionQueue.async { self.applyManualControls() }
            self.showStatus("Настройки применены")
        }
        let nav = UINavigationController(rootViewController: controller)
        if let sheet = nav.sheetPresentationController { sheet.detents = [.medium(), .large()]; sheet.prefersGrabberVisible = true }
        present(nav, animated: true)
    }

    private func showDeviceCapabilities() { showStatus(DeviceInfo.shortSummary(photoOutput: photoOutput)) }

    @objc private func openGallery() {
        var configuration = PHPickerConfiguration(photoLibrary: .shared()); configuration.filter = .any(of: [.images, .videos]); configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration); picker.delegate = self; present(picker, animated: true)
    }

    private func saveCapture(processed: Data, original: Data?, raw: Data?) {
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
    init(completion: @escaping (CapturedFrame?) -> Void) { self.completion = completion }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else { return }
        if photo.isRawPhoto { rawData = data } else { processedData = data }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        guard error == nil, let data = processedData, let image = UIImage(data: data) else { completion(nil); return }
        completion(CapturedFrame(image: image, originalData: data, rawData: rawData))
    }
}

private enum PhotoProcessor {
    static func process(_ images: [UIImage], mode: PhotoMode, settings: ProcessingSettings) -> UIImage? {
        let context = CIContext(options: [.useSoftwareRenderer: false])
        let ciImages = images.compactMap { CIImage(image: $0) }
        guard let reference = ciImages.first else { return nil }
        let aligned = ciImages.enumerated().map { index, image in index == 0 ? image : align(image, to: reference) }
        var output = merge(aligned)
        output = tone(output, mode: mode, settings: settings)
        if mode == .portrait { output = portrait(output) }
        guard let cg = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg, scale: images.first?.scale ?? 1, orientation: .up)
    }

    private static func align(_ image: CIImage, to reference: CIImage) -> CIImage {
        let request = VNTranslationalImageRegistrationRequest(targetedCIImage: image)
        let handler = VNImageRequestHandler(ciImage: reference)
        do { try handler.perform([request]); if let result = request.results?.first as? VNImageTranslationAlignmentObservation { return image.transformed(by: result.alignmentTransform).cropped(to: reference.extent) } } catch { }
        return image.cropped(to: reference.extent)
    }

    private static func merge(_ images: [CIImage]) -> CIImage {
        guard images.count > 1 else { return images[0] }
        let scale = CGFloat(1.0 / Double(images.count))
        func scaled(_ image: CIImage) -> CIImage {
            image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: scale, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: scale, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: scale, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: scale)
            ])
        }
        return images.dropFirst().reduce(scaled(images[0])) { result, image in scaled(image).applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: result]) }
    }

    private static func tone(_ image: CIImage, mode: PhotoMode, settings s: ProcessingSettings) -> CIImage {
        let modeBoost: Float = mode == .night ? 0.25 : (mode == .hdr ? 0.12 : 0)
        var saturation = s.saturation
        var contrast: Float = 1.03 + s.hdrStrength * 0.08
        var temperature = s.temperature
        switch s.style { case 1: temperature -= 250; contrast += 0.04; case 2: saturation -= 0.05; temperature += 120; case 3: saturation += 0.12; contrast += 0.03; default: break }
        var result = image.applyingFilter("CINoiseReduction", parameters: ["inputNoiseLevel": 0.015 + s.denoise * 0.07, "inputSharpness": 0.35])
        result = result.applyingFilter("CIHighlightShadowAdjust", parameters: ["inputShadowAmount": min(1, s.shadows + modeBoost), "inputHighlightAmount": max(0.25, 1 - s.highlights * (s.preserveSky ? 0.85 : 0.55))])
        result = result.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: saturation, kCIInputContrastKey: contrast, kCIInputBrightnessKey: mode == .night ? 0.025 : 0])
        result = result.applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: 0.15 + s.sharpness * 0.9])
        result = result.applyingFilter("CITemperatureAndTint", parameters: ["inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: CGFloat(temperature), y: s.naturalSkin ? 0 : 3)])
        return result.cropped(to: image.extent)
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

private final class ProcessingSettingsViewController: UIViewController, UIDocumentPickerDelegate {
    var onSave: ((ProcessingSettings, Float) -> Void)?
    private var settings: ProcessingSettings
    private var exposure: Float
    private let lensName: String
    private let rawSupported: Bool
    private let deviceSummary: String
    private let stack = UIStackView()

    init(settings: ProcessingSettings, exposure: Float, lensName: String, rawSupported: Bool, deviceSummary: String) { self.settings = settings; self.exposure = exposure; self.lensName = lensName; self.rawSupported = rawSupported; self.deviceSummary = deviceSummary; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground; title = "LIB PATCHER • \(lensName)"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Готово", style: .done, target: self, action: #selector(done))
        let scroll = UIScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(scroll)
        stack.translatesAutoresizingMaskIntoConstraints = false; stack.axis = .vertical; stack.spacing = 14; stack.isLayoutMarginsRelativeArrangement = true; stack.layoutMargins = .init(top: 18, left: 18, bottom: 30, right: 18); scroll.addSubview(stack)
        NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor), scroll.topAnchor.constraint(equalTo: view.topAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor), stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor), stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor), stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor), stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor), stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)])

        let info = UILabel(); info.numberOfLines = 0; info.font = .systemFont(ofSize: 13); info.textColor = .secondaryLabel; info.text = deviceSummary; stack.addArrangedSubview(info)
        let configRow = UIStackView(); configRow.axis = .horizontal; configRow.distribution = .fillEqually; configRow.spacing = 10
        let importButton = UIButton(type: .system); importButton.setTitle("Импорт JSON", for: .normal); importButton.addTarget(self, action: #selector(importConfig), for: .touchUpInside)
        let exportButton = UIButton(type: .system); exportButton.setTitle("Экспорт JSON", for: .normal); exportButton.addTarget(self, action: #selector(exportConfig), for: .touchUpInside)
        configRow.addArrangedSubview(importButton); configRow.addArrangedSubview(exportButton); stack.addArrangedSubview(configRow)
        addHeader("Объединение кадров")
        let frames = UISegmentedControl(items: ["3", "5", "8", "12"]); frames.selectedSegmentIndex = [3,5,8,12].firstIndex(of: settings.frameCount) ?? 1; frames.addAction(UIAction { [weak self] _ in self?.settings.frameCount = [3,5,8,12][frames.selectedSegmentIndex] }, for: .valueChanged); stack.addArrangedSubview(frames)
        addSlider("Сила HDR", 0, 1, settings.hdrStrength) { self.settings.hdrStrength = $0 }
        addSlider("Базовая экспозиция", -2, 2, exposure, valueText: { String(format: "%+.2f EV", $0) }) { self.exposure = $0 }
        addSlider("Шумоподавление", 0, 1, settings.denoise) { self.settings.denoise = $0 }
        addSlider("Резкость", 0, 1, settings.sharpness) { self.settings.sharpness = $0 }
        addSlider("Насыщенность", 0.7, 1.4, settings.saturation) { self.settings.saturation = $0 }
        addSlider("Светлые участки", 0, 1, settings.highlights) { self.settings.highlights = $0 }
        addSlider("Детализация теней", 0, 1, settings.shadows) { self.settings.shadows = $0 }
        addSlider("Температура", 3500, 8500, settings.temperature, valueText: { "\(Int($0)) K" }) { self.settings.temperature = $0 }
        addSwitch("Сохранять небо и яркие лампы", settings.preserveSky) { self.settings.preserveSky = $0 }
        addSwitch("Натуральный оттенок кожи", settings.naturalSkin) { self.settings.naturalSkin = $0 }
        addSwitch("Сохранять исходный кадр", settings.saveOriginal) { self.settings.saveOriginal = $0 }
        addSwitch(rawSupported ? "RAW/ProRAW" : "RAW/ProRAW — не поддерживается", settings.rawEnabled && rawSupported, enabled: rawSupported) { self.settings.rawEnabled = $0 }

        addHeader("Цветовой профиль")
        let styles = UISegmentedControl(items: ["День", "Ночь", "Люди", "Природа"]); styles.selectedSegmentIndex = settings.style; styles.addAction(UIAction { [weak self] _ in self?.settings.style = styles.selectedSegmentIndex }, for: .valueChanged); stack.addArrangedSubview(styles)

        addHeader("Ручное управление")
        addSwitch("Включить Pro-режим", settings.manualEnabled) { self.settings.manualEnabled = $0 }
        addSlider("ISO", 25, 3200, settings.iso, valueText: { "\(Int($0))" }) { self.settings.iso = $0 }
        addSlider("Выдержка", 1.0/8000.0, 1, settings.shutterSeconds, valueText: { $0 >= 0.5 ? String(format: "%.1f с", $0) : "1/\(max(1, Int(1 / $0))) с" }) { self.settings.shutterSeconds = $0 }
        addSlider("Ручной фокус", 0, 1, settings.focus) { self.settings.focus = $0 }
        addSlider("Баланс белого", 3000, 8500, settings.whiteBalance, valueText: { "\(Int($0)) K" }) { self.settings.whiteBalance = $0 }
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

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first, let data = try? Data(contentsOf: url), let config = try? JSONDecoder().decode(TigrConfig.self, from: data) else {
            let alert = UIAlertController(title: "Ошибка", message: "Не удалось прочитать конфиг Tigr JSON.", preferredStyle: .alert); alert.addAction(UIAlertAction(title: "OK", style: .default)); present(alert, animated: true); return
        }
        settings = config.applied(to: settings); exposure = min(max(config.exposure, -2), 2)
        let alert = UIAlertController(title: "Конфиг импортирован", message: "\(config.name) применён к объективу \(lensName).", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Применить", style: .default) { [weak self] _ in guard let self else { return }; self.onSave?(self.settings, self.exposure); self.dismiss(animated: true) })
        present(alert, animated: true)
    }

    @objc private func done() { onSave?(settings, exposure); dismiss(animated: true) }
}

private enum DeviceInfo {
    static func machine() -> String { var info = utsname(); uname(&info); return withUnsafePointer(to: &info.machine) { $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) } } }
    static func hasLens(_ type: AVCaptureDevice.DeviceType) -> Bool { !AVCaptureDevice.DiscoverySession(deviceTypes: [type], mediaType: .video, position: .back).devices.isEmpty }
    static func shortSummary(photoOutput: AVCapturePhotoOutput) -> String { "\(machine()) • RAW \(photoOutput.availableRawPhotoPixelFormatTypes.isEmpty ? "нет" : "да")" }
    static func summary(photoOutput: AVCapturePhotoOutput) -> String {
        "Устройство: \(machine())\n0.5×: \(hasLens(.builtInUltraWideCamera) ? "поддерживается" : "нет") • 2×: \(hasLens(.builtInTelephotoCamera) ? "поддерживается" : "нет")\nRAW/ProRAW: \(photoOutput.availableRawPhotoPixelFormatTypes.isEmpty ? "не поддерживается" : "поддерживается") • Портретная глубина: \(photoOutput.isDepthDataDeliverySupported ? "да" : "программное размытие")"
    }
}

extension CameraViewController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async { self.setRecordingUI(active: false) }
        guard error == nil else { try? FileManager.default.removeItem(at: outputFileURL); DispatchQueue.main.async { self.showStatus("Ошибка записи") }; return }
        saveVideo(outputFileURL)
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

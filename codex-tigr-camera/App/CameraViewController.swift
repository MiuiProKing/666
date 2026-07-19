import AVFoundation
import Photos
import PhotosUI
import UIKit

final class CameraViewController: UIViewController {
    private enum CaptureMode: Int { case photo, video }

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.tigr.camera.session", qos: .userInitiated)
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var isConfigured = false
    private var currentMode: CaptureMode = .photo
    private var flashMode: AVCaptureDevice.FlashMode = .off
    private var timerSeconds = 0
    private var gridVisible = true
    private var countdownTimer: Timer?
    private var recordingStartedAt: Date?
    private var recordingTimer: Timer?

    private let previewView = UIView()
    private lazy var previewLayer = AVCaptureVideoPreviewLayer(session: session)
    private let topBar = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let bottomBar = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let titleLabel = UILabel()
    private let flashButton = UIButton(type: .system)
    private let timerButton = UIButton(type: .system)
    private let gridButton = UIButton(type: .system)
    private let switchButton = UIButton(type: .system)
    private let galleryButton = UIButton(type: .system)
    private let shutterButton = UIButton(type: .custom)
    private let modeControl = UISegmentedControl(items: ["PHOTO", "VIDEO"])
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

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Google Camera Tigr"
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        topBar.contentView.addSubview(titleLabel)

        configureTopButton(flashButton, image: "bolt.slash.fill", action: #selector(toggleFlash))
        configureTopButton(timerButton, image: "timer", action: #selector(toggleTimer))
        configureTopButton(gridButton, image: "grid", action: #selector(toggleGrid))
        [flashButton, timerButton, gridButton].forEach { topBar.contentView.addSubview($0) }

        modeControl.translatesAutoresizingMaskIntoConstraints = false
        modeControl.selectedSegmentIndex = 0
        modeControl.selectedSegmentTintColor = UIColor(red: 0.98, green: 0.74, blue: 0.18, alpha: 1)
        modeControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        modeControl.setTitleTextAttributes([.foregroundColor: UIColor.black], for: .selected)
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
        exposureSlider.value = 0
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
        for (title, tag) in [("0.5x", 5), ("1x", 10), ("2x", 20)] {
            let button = UIButton(type: .system)
            button.setTitle(title, for: .normal)
            button.setTitleColor(.white, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
            button.backgroundColor = UIColor.black.withAlphaComponent(0.55)
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
        statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.68)
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

        let tap = UITapGestureRecognizer(target: self, action: #selector(focusTapped(_:)))
        previewView.addGestureRecognizer(tap)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinchZoom(_:)))
        previewView.addGestureRecognizer(pinch)

        NSLayoutConstraint.activate([
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewView.topAnchor.constraint(equalTo: view.topAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            gridView.leadingAnchor.constraint(equalTo: previewView.leadingAnchor),
            gridView.trailingAnchor.constraint(equalTo: previewView.trailingAnchor),
            gridView.topAnchor.constraint(equalTo: previewView.topAnchor),
            gridView.bottomAnchor.constraint(equalTo: previewView.bottomAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.topAnchor.constraint(equalTo: view.topAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 82),
            titleLabel.leadingAnchor.constraint(equalTo: topBar.contentView.leadingAnchor, constant: 18),
            titleLabel.bottomAnchor.constraint(equalTo: topBar.contentView.bottomAnchor, constant: -14),
            gridButton.trailingAnchor.constraint(equalTo: topBar.contentView.trailingAnchor, constant: -12),
            gridButton.bottomAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 7),
            timerButton.trailingAnchor.constraint(equalTo: gridButton.leadingAnchor, constant: -6),
            timerButton.centerYAnchor.constraint(equalTo: gridButton.centerYAnchor),
            flashButton.trailingAnchor.constraint(equalTo: timerButton.leadingAnchor, constant: -6),
            flashButton.centerYAnchor.constraint(equalTo: gridButton.centerYAnchor),
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 235),
            modeControl.topAnchor.constraint(equalTo: bottomBar.contentView.topAnchor, constant: 14),
            modeControl.centerXAnchor.constraint(equalTo: bottomBar.contentView.centerXAnchor),
            modeControl.widthAnchor.constraint(equalToConstant: 210),
            exposureLabel.leadingAnchor.constraint(equalTo: bottomBar.contentView.leadingAnchor, constant: 24),
            exposureLabel.topAnchor.constraint(equalTo: modeControl.bottomAnchor, constant: 14),
            exposureLabel.widthAnchor.constraint(equalToConstant: 52),
            exposureSlider.leadingAnchor.constraint(equalTo: exposureLabel.trailingAnchor, constant: 8),
            exposureSlider.trailingAnchor.constraint(equalTo: bottomBar.contentView.trailingAnchor, constant: -24),
            exposureSlider.centerYAnchor.constraint(equalTo: exposureLabel.centerYAnchor),
            shutterButton.centerXAnchor.constraint(equalTo: bottomBar.contentView.centerXAnchor),
            shutterButton.bottomAnchor.constraint(equalTo: bottomBar.contentView.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            shutterButton.widthAnchor.constraint(equalToConstant: 72),
            shutterButton.heightAnchor.constraint(equalToConstant: 72),
            galleryButton.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor),
            galleryButton.trailingAnchor.constraint(equalTo: shutterButton.leadingAnchor, constant: -54),
            galleryButton.widthAnchor.constraint(equalToConstant: 54),
            galleryButton.heightAnchor.constraint(equalToConstant: 54),
            switchButton.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor),
            switchButton.leadingAnchor.constraint(equalTo: shutterButton.trailingAnchor, constant: 54),
            switchButton.widthAnchor.constraint(equalToConstant: 54),
            switchButton.heightAnchor.constraint(equalToConstant: 54),
            zoomStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            zoomStack.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -14),
            zoomStack.widthAnchor.constraint(equalToConstant: 190),
            zoomStack.heightAnchor.constraint(equalToConstant: 36),
            countdownLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            countdownLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            recordingLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            recordingLabel.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 12),
            recordingLabel.widthAnchor.constraint(equalToConstant: 104),
            recordingLabel.heightAnchor.constraint(equalToConstant: 28),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: zoomStack.topAnchor, constant: -16),
            statusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),
            statusLabel.heightAnchor.constraint(equalToConstant: 34)
        ])
    }

    private func configureTopButton(_ button: UIButton, image: String, action: Selector) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: image), for: .normal)
        button.tintColor = .white
        button.addTarget(self, action: action, for: .touchUpInside)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 38),
            button.heightAnchor.constraint(equalToConstant: 38)
        ])
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
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                DispatchQueue.main.async {
                    allowed ? self?.configureSession() : self?.showPermissionMessage()
                }
            }
        default:
            showPermissionMessage()
        }
    }

    private func showPermissionMessage() {
        let alert = UIAlertController(
            title: "Camera access required",
            message: "Open Settings and allow camera access for Google Camera Tigr.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Settings", style: .default) { _ in
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self, !self.isConfigured else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            do {
                let device = self.cameraDevice(position: .back, lens: .builtInWideAngleCamera)
                guard let device else { throw CameraError.noCamera }
                let input = try AVCaptureDeviceInput(device: device)
                guard self.session.canAddInput(input) else { throw CameraError.inputUnavailable }
                self.session.addInput(input)
                self.videoInput = input
                guard self.session.canAddOutput(self.photoOutput), self.session.canAddOutput(self.movieOutput) else {
                    throw CameraError.outputUnavailable
                }
                self.session.addOutput(self.photoOutput)
                self.session.addOutput(self.movieOutput)
                self.photoOutput.isHighResolutionCaptureEnabled = true
                self.isConfigured = true
                self.session.commitConfiguration()
                self.session.startRunning()
            } catch {
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.showStatus("Camera unavailable") }
            }
        }
    }

    private func startSessionIfPossible() {
        sessionQueue.async { [weak self] in
            guard let self, self.isConfigured, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    private func cameraDevice(position: AVCaptureDevice.Position, lens: AVCaptureDevice.DeviceType) -> AVCaptureDevice? {
        let requested = AVCaptureDevice.DiscoverySession(
            deviceTypes: [lens], mediaType: .video, position: position
        ).devices.first
        if let requested { return requested }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    private func replaceVideoInput(position: AVCaptureDevice.Position, lens: AVCaptureDevice.DeviceType) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.cameraDevice(position: position, lens: lens) else { return }
            do {
                let newInput = try AVCaptureDeviceInput(device: device)
                self.session.beginConfiguration()
                if let oldInput = self.videoInput { self.session.removeInput(oldInput) }
                if self.session.canAddInput(newInput) {
                    self.session.addInput(newInput)
                    self.videoInput = newInput
                } else if let oldInput = self.videoInput, self.session.canAddInput(oldInput) {
                    self.session.addInput(oldInput)
                }
                self.session.commitConfiguration()
                DispatchQueue.main.async {
                    self.exposureSlider.value = 0
                    self.exposureLabel.text = "EV 0.0"
                }
            } catch {
                DispatchQueue.main.async { self.showStatus("Lens unavailable") }
            }
        }
    }

    @objc private func toggleFlash() {
        switch flashMode {
        case .off: flashMode = .on
        case .on: flashMode = .auto
        default: flashMode = .off
        }
        let symbol: String
        switch flashMode {
        case .on: symbol = "bolt.fill"
        case .auto: symbol = "bolt.badge.a.fill"
        default: symbol = "bolt.slash.fill"
        }
        flashButton.setImage(UIImage(systemName: symbol), for: .normal)
    }

    @objc private func toggleTimer() {
        timerSeconds = timerSeconds == 0 ? 3 : (timerSeconds == 3 ? 10 : 0)
        timerButton.setTitle(timerSeconds == 0 ? nil : "\(timerSeconds)", for: .normal)
        timerButton.setImage(timerSeconds == 0 ? UIImage(systemName: "timer") : nil, for: .normal)
        showStatus(timerSeconds == 0 ? "Timer off" : "Timer \(timerSeconds)s")
    }

    @objc private func toggleGrid() {
        gridVisible.toggle()
        gridView.isHidden = !gridVisible
        gridButton.tintColor = gridVisible ? UIColor(red: 0.98, green: 0.74, blue: 0.18, alpha: 1) : .white
    }

    @objc private func modeChanged() {
        currentMode = CaptureMode(rawValue: modeControl.selectedSegmentIndex) ?? .photo
        let isVideo = currentMode == .video
        shutterButton.backgroundColor = isVideo ? .systemRed : .white
        flashButton.isEnabled = !isVideo
        flashButton.alpha = isVideo ? 0.35 : 1
        sessionQueue.async { [weak self] in
            self?.session.beginConfiguration()
            self?.session.sessionPreset = isVideo ? .high : .photo
            self?.session.commitConfiguration()
        }
    }

    @objc private func exposureChanged() {
        let value = exposureSlider.value
        exposureLabel.text = String(format: "EV %.1f", value)
        sessionQueue.async { [weak self] in
            guard let device = self?.videoInput?.device else { return }
            do {
                try device.lockForConfiguration()
                let clamped = min(max(value, device.minExposureTargetBias), device.maxExposureTargetBias)
                device.setExposureTargetBias(clamped)
                device.unlockForConfiguration()
            } catch { }
        }
    }

    @objc private func shutterTapped() {
        if currentMode == .video {
            movieOutput.isRecording ? stopRecording() : prepareVideoRecording()
        } else {
            beginCountdown(seconds: timerSeconds) { [weak self] in self?.capturePhoto() }
        }
    }

    private func beginCountdown(seconds: Int, completion: @escaping () -> Void) {
        guard seconds > 0 else { completion(); return }
        var remaining = seconds
        countdownLabel.text = "\(remaining)"
        countdownLabel.isHidden = false
        shutterButton.isEnabled = false
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            remaining -= 1
            if remaining <= 0 {
                timer.invalidate()
                self?.countdownLabel.isHidden = true
                self?.shutterButton.isEnabled = true
                completion()
            } else {
                self?.countdownLabel.text = "\(remaining)"
            }
        }
    }

    private func capturePhoto() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let settings = AVCapturePhotoSettings()
            settings.isHighResolutionPhotoEnabled = true
            if self.videoInput?.device.hasFlash == true { settings.flashMode = self.flashMode }
            if let connection = self.photoOutput.connection(with: .video) {
                connection.videoOrientation = .portrait
                connection.isVideoMirrored = self.videoInput?.device.position == .front
            }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    private func prepareVideoRecording() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                DispatchQueue.main.async { self?.startRecording() }
            }
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        sessionQueue.async { [weak self] in
            guard let self, !self.movieOutput.isRecording else { return }
            self.addAudioInputIfAllowed()
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("TigrCamera-\(UUID().uuidString).mov")
            if let connection = self.movieOutput.connection(with: .video) {
                connection.videoOrientation = .portrait
                connection.isVideoMirrored = self.videoInput?.device.position == .front
            }
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
            DispatchQueue.main.async { self.setRecordingUI(active: true) }
        }
    }

    private func addAudioInputIfAllowed() {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized, audioInput == nil,
              let device = AVCaptureDevice.default(for: .audio), let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        if session.canAddInput(input) {
            session.addInput(input)
            audioInput = input
        }
        session.commitConfiguration()
    }

    private func stopRecording() {
        sessionQueue.async { [weak self] in self?.movieOutput.stopRecording() }
        setRecordingUI(active: false)
    }

    private func setRecordingUI(active: Bool) {
        recordingTimer?.invalidate()
        recordingStartedAt = active ? Date() : nil
        recordingLabel.isHidden = !active
        shutterButton.layer.cornerRadius = active ? 12 : 36
        shutterButton.transform = active ? CGAffineTransform(scaleX: 0.62, y: 0.62) : .identity
        if active {
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                guard let start = self?.recordingStartedAt else { return }
                let seconds = Int(Date().timeIntervalSince(start))
                self?.recordingLabel.text = String(format: " REC %02d:%02d ", seconds / 60, seconds % 60)
            }
        }
    }

    @objc private func switchCamera() {
        guard !movieOutput.isRecording else { return }
        let position: AVCaptureDevice.Position = videoInput?.device.position == .back ? .front : .back
        replaceVideoInput(position: position, lens: .builtInWideAngleCamera)
    }

    @objc private func zoomPreset(_ sender: UIButton) {
        guard videoInput?.device.position != .front else {
            applyZoom(sender.tag == 20 ? 2 : 1)
            return
        }
        switch sender.tag {
        case 5: replaceVideoInput(position: .back, lens: .builtInUltraWideCamera)
        case 20: replaceVideoInput(position: .back, lens: .builtInTelephotoCamera)
        default: replaceVideoInput(position: .back, lens: .builtInWideAngleCamera)
        }
        zoomStack.arrangedSubviews.compactMap { $0 as? UIButton }.forEach {
            $0.backgroundColor = $0 == sender
                ? UIColor(red: 0.98, green: 0.74, blue: 0.18, alpha: 0.8)
                : UIColor.black.withAlphaComponent(0.55)
        }
    }

    @objc private func pinchZoom(_ gesture: UIPinchGestureRecognizer) {
        guard let device = videoInput?.device else { return }
        if gesture.state == .changed {
            let desired = device.videoZoomFactor * gesture.scale
            applyZoom(desired)
            gesture.scale = 1
        }
    }

    private func applyZoom(_ factor: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let device = self?.videoInput?.device else { return }
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = min(max(factor, 1), min(device.activeFormat.videoMaxZoomFactor, 8))
                device.unlockForConfiguration()
            } catch { }
        }
    }

    @objc private func focusTapped(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: previewView)
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)
        focusRing.center = point
        focusRing.transform = CGAffineTransform(scaleX: 1.35, y: 1.35)
        focusRing.alpha = 1
        UIView.animate(withDuration: 0.25, animations: {
            self.focusRing.transform = .identity
        }) { _ in
            UIView.animate(withDuration: 0.35, delay: 0.45, options: [], animations: { self.focusRing.alpha = 0 })
        }
        sessionQueue.async { [weak self] in
            guard let device = self?.videoInput?.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = .continuousAutoExposure
                }
                device.unlockForConfiguration()
            } catch { }
        }
    }

    @objc private func openGallery() {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .any(of: [.images, .videos])
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func savePhoto(_ data: Data) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { self?.showStatus("Photo permission denied") }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            }) { success, _ in
                DispatchQueue.main.async { self?.showStatus(success ? "Photo saved" : "Save failed") }
            }
        }
    }

    private func saveVideo(_ url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard status == .authorized || status == .limited else {
                try? FileManager.default.removeItem(at: url)
                DispatchQueue.main.async { self?.showStatus("Photo permission denied") }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { success, _ in
                try? FileManager.default.removeItem(at: url)
                DispatchQueue.main.async { self?.showStatus(success ? "Video saved" : "Save failed") }
            }
        }
    }

    private func showStatus(_ text: String) {
        statusLabel.text = "  \(text)  "
        UIView.animate(withDuration: 0.2, animations: { self.statusLabel.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.35, delay: 1.4, options: [], animations: { self.statusLabel.alpha = 0 })
        }
    }

    private enum CameraError: Error { case noCamera, inputUnavailable, outputUnavailable }
}

extension CameraViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil, let data = photo.fileDataRepresentation() else {
            showStatus("Capture failed")
            return
        }
        if let image = UIImage(data: data) {
            galleryButton.setImage(image.withRenderingMode(.alwaysOriginal), for: .normal)
            galleryButton.imageView?.contentMode = .scaleAspectFill
            galleryButton.clipsToBounds = true
        }
        savePhoto(data)
    }
}

extension CameraViewController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        DispatchQueue.main.async { self.setRecordingUI(active: false) }
        guard error == nil else {
            try? FileManager.default.removeItem(at: outputFileURL)
            DispatchQueue.main.async { self.showStatus("Recording failed") }
            return
        }
        saveVideo(outputFileURL)
    }
}

extension CameraViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
    }
}

private final class GridOverlayView: UIView {
    override class var layerClass: AnyClass { CAShapeLayer.self }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let shape = layer as? CAShapeLayer else { return }
        let path = UIBezierPath()
        for fraction in [CGFloat(1.0 / 3.0), CGFloat(2.0 / 3.0)] {
            path.move(to: CGPoint(x: bounds.width * fraction, y: 0))
            path.addLine(to: CGPoint(x: bounds.width * fraction, y: bounds.height))
            path.move(to: CGPoint(x: 0, y: bounds.height * fraction))
            path.addLine(to: CGPoint(x: bounds.width, y: bounds.height * fraction))
        }
        shape.path = path.cgPath
        shape.strokeColor = UIColor.white.withAlphaComponent(0.34).cgColor
        shape.fillColor = UIColor.clear.cgColor
        shape.lineWidth = 0.7
    }
}

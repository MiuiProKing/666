import AVFoundation
import Combine
import OSLog
import UIKit

@MainActor
final class CameraEngine: ObservableObject {
    @Published private(set) var authorizationState: CameraAuthorizationState = .notDetermined
    @Published private(set) var isRunning = false
    @Published private(set) var isCapturing = false
    @Published private(set) var availableLenses: [CameraLens] = []
    @Published private(set) var selectedLensID: CameraLens.ID?
    @Published private(set) var position: CameraPosition = .back
    @Published private(set) var exposureRange: ClosedRange<Float> = -2...2
    @Published private(set) var hasFlash = false
    @Published private(set) var isoRange: ClosedRange<Float> = 50...800
    @Published private(set) var shutterStopsRange: ClosedRange<Float> = -12...0
    @Published private(set) var isManualFocusSupported = false
    @Published private(set) var lastThumbnail: UIImage?
    @Published private(set) var errorMessage: String?
    @Published private(set) var statusMessage: String?
    @Published private(set) var isThermallyConstrained = false
    @Published var exposureBias: Float = 0
    @Published var flashMode: FlashMode = .auto
    @Published var isManualMode = false
    @Published var manualISO: Float = 100
    @Published var shutterStops: Float = -8
    @Published var manualFocusPosition: Float = 0.5

    let session = AVCaptureSession()

    var visibleLenses: [CameraLens] {
        availableLenses.filter { $0.position == position }
    }

    private let permissionManager: CameraPermissionProviding
    private let photoLibrary: PhotoLibrarySaving
    private let processor: ImageProcessing
    private let settings: AppSettings
    private let presetStore: PresetStore
    private let sessionQueue = DispatchQueue(
        label: "com.yourname.lumorax.camera.session",
        qos: .userInitiated
    )
    private let photoOutput = AVCapturePhotoOutput()
    private var currentInput: AVCaptureDeviceInput?
    private var devicesByID: [String: AVCaptureDevice] = [:]
    private var captureDelegates: [Int64: PhotoCaptureDelegate] = [:]
    private var thermalObserver: NSObjectProtocol?
    private let logger = Logger(subsystem: "com.yourname.lumorax", category: "Camera")

    init(
        permissionManager: CameraPermissionProviding,
        photoLibrary: PhotoLibrarySaving,
        processor: ImageProcessing,
        settings: AppSettings,
        presetStore: PresetStore
    ) {
        self.permissionManager = permissionManager
        self.photoLibrary = photoLibrary
        self.processor = processor
        self.settings = settings
        self.presetStore = presetStore
        observeThermalState()
    }

    deinit {
        if let thermalObserver {
            NotificationCenter.default.removeObserver(thermalObserver)
        }
    }

    func start() async {
        var state = permissionManager.currentState()
        authorizationState = state

        if state == .notDetermined {
            state = await permissionManager.requestAccess()
            authorizationState = state
        }

        guard state == .authorized else { return }

        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }

                do {
                    if self.currentInput == nil {
                        try self.configureSession()
                    }
                    if !self.session.isRunning {
                        self.session.startRunning()
                    }
                    Task { @MainActor in
                        self.isRunning = self.session.isRunning
                        continuation.resume()
                    }
                } catch {
                    self.logger.error("Camera start failed: \(error.localizedDescription, privacy: .public)")
                    Task { @MainActor in
                        self.errorMessage = error.localizedDescription
                        continuation.resume()
                    }
                }
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            Task { @MainActor in self.isRunning = false }
        }
    }

    func selectLens(id: CameraLens.ID) {
        switchToDevice(id: id)
    }

    func switchCamera() {
        let target: CameraPosition = position == .back ? .front : .back
        guard let lens = availableLenses.first(where: {
            $0.position == target && $0.deviceType == .builtInWideAngleCamera
        }) ?? availableLenses.first(where: { $0.position == target }) else {
            errorMessage = "На устройстве нет камеры для переключения."
            return
        }
        switchToDevice(id: lens.id)
    }

    func focus(at devicePoint: CGPoint) {
        sessionQueue.async { [weak self] in
            guard let device = self?.currentInput?.device else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }

                if device.isFocusPointOfInterestSupported,
                   device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = .continuousAutoFocus
                }
                if device.isExposurePointOfInterestSupported,
                   device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = .continuousAutoExposure
                }
            } catch {
                self?.logger.error("Focus configuration failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func setExposureBias(_ value: Float) {
        exposureBias = min(max(value, exposureRange.lowerBound), exposureRange.upperBound)
        let clampedValue = exposureBias
        sessionQueue.async { [weak self] in
            guard let device = self?.currentInput?.device else { return }
            do {
                try device.lockForConfiguration()
                device.setExposureTargetBias(clampedValue, completionHandler: nil)
                device.unlockForConfiguration()
            } catch {
                self?.logger.error("Exposure configuration failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func setManualMode(_ enabled: Bool) {
        isManualMode = enabled
        if enabled {
            applyManualExposure()
        } else {
            restoreAutomaticControls()
        }
    }

    func setManualISO(_ value: Float) {
        manualISO = min(max(value, isoRange.lowerBound), isoRange.upperBound)
        applyManualExposure()
    }

    func setManualShutterStops(_ value: Float) {
        shutterStops = min(
            max(value, shutterStopsRange.lowerBound),
            shutterStopsRange.upperBound
        )
        applyManualExposure()
    }

    func setManualFocus(_ value: Float) {
        manualFocusPosition = min(max(value, 0), 1)
        let position = manualFocusPosition
        sessionQueue.async { [weak self] in
            guard let device = self?.currentInput?.device,
                  device.isFocusModeSupported(.locked) else { return }
            do {
                try device.lockForConfiguration()
                device.setFocusModeLocked(lensPosition: position, completionHandler: nil)
                device.unlockForConfiguration()
            } catch {
                self?.logger.error("Manual focus failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func cycleFlash() {
        guard hasFlash else { return }
        switch flashMode {
        case .off: flashMode = .auto
        case .auto: flashMode = .on
        case .on: flashMode = .off
        }
    }

    func capturePhoto() {
        guard authorizationState == .authorized, isRunning, !isCapturing else { return }
        isCapturing = true
        statusMessage = nil

        let requestedQuality = settings.captureQuality
        let actualQuality: CaptureQuality = isThermallyConstrained ? .balanced : requestedQuality
        let outputFormat = settings.outputFormat
        let saveOriginal = settings.saveOriginal
        let mirrorSelfie = settings.mirrorSelfie
        let selectedPreset = presetStore.selectedPreset
        let requestedFlash = flashMode
        let orientation = Self.currentVideoOrientation()

        sessionQueue.async { [weak self] in
            guard let self else { return }

            let codec: AVVideoCodecType = self.photoOutput.availablePhotoCodecTypes.contains(.hevc)
                ? .hevc
                : .jpeg
            let captureSettings = AVCapturePhotoSettings(format: [
                AVVideoCodecKey: codec
            ])
            captureSettings.photoQualityPrioritization = actualQuality.photoQualityPrioritization

            if self.currentInput?.device.hasFlash == true {
                captureSettings.flashMode = requestedFlash.avMode
            }

            if let connection = self.photoOutput.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = orientation
                }
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = self.currentInput?.device.position == .front
                        && mirrorSelfie
                }
            }

            let captureID = captureSettings.uniqueID
            let delegate = PhotoCaptureDelegate { [weak self] result in
                guard let self else { return }
                self.sessionQueue.async {
                    self.captureDelegates[captureID] = nil
                }
                Task { @MainActor in
                    await self.finishCapture(
                        result,
                        preset: selectedPreset,
                        outputFormat: outputFormat,
                        saveOriginal: saveOriginal
                    )
                }
            }
            self.captureDelegates[captureID] = delegate
            self.photoOutput.capturePhoto(with: captureSettings, delegate: delegate)
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    func clearStatus() {
        statusMessage = nil
    }

    private func configureSession() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo

        let devices = discoverDevices()
        guard let initialDevice = devices.first(where: {
            $0.position == .back && $0.deviceType == .builtInWideAngleCamera
        }) ?? devices.first else {
            throw CameraError.noCamera
        }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: initialDevice)
        } catch {
            throw CameraError.cannotCreateInput
        }

        guard session.canAddInput(input) else { throw CameraError.cannotAddInput }
        session.addInput(input)

        guard session.canAddOutput(photoOutput) else { throw CameraError.cannotAddOutput }
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .quality
        currentInput = input

        let lensModels = devices.map(Self.makeLens)
        devicesByID = Dictionary(uniqueKeysWithValues: devices.map { ($0.uniqueID, $0) })

        Task { @MainActor in
            self.availableLenses = lensModels
            self.applyPublishedDeviceState(initialDevice)
        }
    }

    private func discoverDevices() -> [AVCaptureDevice] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInWideAngleCamera,
                .builtInUltraWideCamera,
                .builtInTelephotoCamera,
                .builtInTrueDepthCamera
            ],
            mediaType: .video,
            position: .unspecified
        )

        var seen = Set<String>()
        return discovery.devices.filter { seen.insert($0.uniqueID).inserted }
    }

    private func switchToDevice(id: String) {
        sessionQueue.async { [weak self] in
            guard let self,
                  let device = self.devicesByID[id],
                  self.currentInput?.device.uniqueID != id else { return }

            do {
                let newInput = try AVCaptureDeviceInput(device: device)
                self.session.beginConfiguration()
                if let oldInput = self.currentInput {
                    self.session.removeInput(oldInput)
                }

                if self.session.canAddInput(newInput) {
                    self.session.addInput(newInput)
                    self.currentInput = newInput
                    self.session.commitConfiguration()
                    Task { @MainActor in
                        self.applyPublishedDeviceState(device)
                    }
                } else {
                    if let oldInput = self.currentInput,
                       self.session.canAddInput(oldInput) {
                        self.session.addInput(oldInput)
                    }
                    self.session.commitConfiguration()
                    throw CameraError.cannotAddInput
                }
            } catch {
                self.logger.error("Camera switch failed: \(error.localizedDescription, privacy: .public)")
                Task { @MainActor in self.errorMessage = error.localizedDescription }
            }
        }
    }

    private func applyPublishedDeviceState(_ device: AVCaptureDevice) {
        selectedLensID = device.uniqueID
        position = device.position == .front ? .front : .back
        exposureRange = device.minExposureTargetBias...device.maxExposureTargetBias
        exposureBias = 0
        hasFlash = device.hasFlash
        isoRange = device.activeFormat.minISO...device.activeFormat.maxISO
        manualISO = device.iso
        manualFocusPosition = device.lensPosition
        isManualFocusSupported = device.isFocusModeSupported(.locked)

        let minimumSeconds = max(
            CMTimeGetSeconds(device.activeFormat.minExposureDuration),
            1.0 / 100_000.0
        )
        let maximumSeconds = max(
            minimumSeconds,
            CMTimeGetSeconds(device.activeFormat.maxExposureDuration)
        )
        shutterStopsRange = Float(log2(minimumSeconds))...Float(log2(maximumSeconds))
        let currentSeconds = max(CMTimeGetSeconds(device.exposureDuration), minimumSeconds)
        shutterStops = Float(log2(currentSeconds))

        if !device.hasFlash { flashMode = .off }
        if isManualMode { applyManualExposure() }
    }

    private func applyManualExposure() {
        guard isManualMode else { return }
        let requestedISO = manualISO
        let requestedStops = shutterStops

        sessionQueue.async { [weak self] in
            guard let device = self?.currentInput?.device,
                  device.isExposureModeSupported(.custom) else { return }

            let minimumSeconds = CMTimeGetSeconds(device.activeFormat.minExposureDuration)
            let maximumSeconds = CMTimeGetSeconds(device.activeFormat.maxExposureDuration)
            let requestedSeconds = pow(2.0, Double(requestedStops))
            let seconds = min(max(requestedSeconds, minimumSeconds), maximumSeconds)
            let duration = CMTimeMakeWithSeconds(seconds, preferredTimescale: 1_000_000_000)
            let iso = min(max(requestedISO, device.activeFormat.minISO), device.activeFormat.maxISO)

            do {
                try device.lockForConfiguration()
                device.setExposureModeCustom(
                    duration: duration,
                    iso: iso,
                    completionHandler: nil
                )
                device.unlockForConfiguration()
            } catch {
                self?.logger.error("Manual exposure failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func restoreAutomaticControls() {
        exposureBias = 0
        sessionQueue.async { [weak self] in
            guard let device = self?.currentInput?.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                    device.setExposureTargetBias(0, completionHandler: nil)
                }
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                device.unlockForConfiguration()
            } catch {
                self?.logger.error("Auto controls restore failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func finishCapture(
        _ result: Result<Data, Error>,
        preset: PresetModel,
        outputFormat: PhotoOutputFormat,
        saveOriginal: Bool
    ) async {
        defer { isCapturing = false }

        do {
            let originalData = try result.get()
            let timestamp = Int(Date().timeIntervalSince1970)

            if saveOriginal {
                try await photoLibrary.savePhoto(
                    data: originalData,
                    filename: "LUMORAX_\(timestamp)_ORIGINAL.heic"
                )
            }

            let processedData = try await processor.process(
                photoData: originalData,
                preset: preset,
                outputFormat: outputFormat
            )
            let fileExtension = outputFormat == .heif ? "heic" : "jpg"
            try await photoLibrary.savePhoto(
                data: processedData,
                filename: "LUMORAX_\(timestamp).\(fileExtension)"
            )

            lastThumbnail = UIImage(data: processedData)
            statusMessage = saveOriginal
                ? "Обработанный снимок и оригинал сохранены"
                : "Снимок сохранён"
            logger.info("Photo saved with preset \(preset.id, privacy: .public)")
        } catch {
            logger.error("Photo capture pipeline failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    private func observeThermalState() {
        updateThermalState()
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateThermalState() }
        }
    }

    private func updateThermalState() {
        switch ProcessInfo.processInfo.thermalState {
        case .serious, .critical:
            isThermallyConstrained = true
        default:
            isThermallyConstrained = false
        }
    }

    private static func makeLens(_ device: AVCaptureDevice) -> CameraLens {
        let position: CameraPosition = device.position == .front ? .front : .back
        let shortName: String
        switch device.deviceType {
        case .builtInUltraWideCamera: shortName = "0.5×"
        case .builtInTelephotoCamera: shortName = "TELE"
        case .builtInTrueDepthCamera: shortName = "FRONT"
        default: shortName = position == .front ? "FRONT" : "1×"
        }
        return CameraLens(
            id: device.uniqueID,
            name: device.localizedName,
            shortName: shortName,
            position: position,
            deviceType: device.deviceType
        )
    }

    private static func currentVideoOrientation() -> AVCaptureVideoOrientation {
        switch UIDevice.current.orientation {
        case .landscapeLeft: return .landscapeRight
        case .landscapeRight: return .landscapeLeft
        case .portraitUpsideDown: return .portraitUpsideDown
        default: return .portrait
        }
    }
}

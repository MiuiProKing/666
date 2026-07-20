import SwiftUI
import UIKit

struct CameraScreen: View {
    @StateObject private var camera: CameraEngine
    @StateObject private var settings: AppSettings
    @StateObject private var presetStore: PresetStore
    @State private var isShowingSettings = false

    init(camera: CameraEngine, settings: AppSettings, presetStore: PresetStore) {
        _camera = StateObject(wrappedValue: camera)
        _settings = StateObject(wrappedValue: settings)
        _presetStore = StateObject(wrappedValue: presetStore)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch camera.authorizationState {
            case .authorized:
                cameraInterface
            case .notDetermined:
                ProgressView("Подготовка камеры…")
                    .tint(AppTheme.gold)
                    .foregroundStyle(.white)
            case .denied, .restricted:
                PermissionDeniedView()
            }
        }
        .task { await camera.start() }
        .sheet(isPresented: $isShowingSettings) {
            SettingsScreen(settings: settings)
        }
        .alert(
            "LUMORA X",
            isPresented: Binding(
                get: { camera.errorMessage != nil },
                set: { if !$0 { camera.dismissError() } }
            )
        ) {
            Button("OK", role: .cancel) { camera.dismissError() }
        } message: {
            Text(camera.errorMessage ?? "Неизвестная ошибка")
        }
    }

    private var cameraInterface: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 16)
                    .frame(height: 58)

                ZStack {
                    CameraPreview(
                        session: camera.session,
                        isFrontCamera: camera.position == .front,
                        onFocus: camera.focus
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    if settings.gridEnabled {
                        RuleOfThirdsGrid()
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .allowsHitTesting(false)
                    }

                    VStack {
                        HStack {
                            if camera.isThermallyConstrained {
                                Label("THERMAL SAFE", systemImage: "thermometer.high")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 6)
                                    .background(.black.opacity(0.58), in: Capsule())
                                    .foregroundStyle(.orange)
                            }
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(12)

                    if !camera.isRunning {
                        ProgressView()
                            .controlSize(.large)
                            .tint(AppTheme.gold)
                    }
                }
                .padding(.horizontal, 8)
                .frame(height: max(320, geometry.size.height * 0.57))

                controls
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .overlay(alignment: .top) {
                if let status = camera.statusMessage {
                    Text(status)
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 64)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .task(id: status) {
                            try? await Task.sleep(nanoseconds: 2_200_000_000)
                            camera.clearStatus()
                        }
                }
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Text("LUMORA")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .tracking(2.5)
            Text("X")
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.gold)

            Spacer()

            if camera.hasFlash {
                TopBarButton(
                    systemName: flashIcon,
                    label: "Вспышка: \(camera.flashMode.rawValue)"
                ) {
                    camera.cycleFlash()
                }
            }

            Text(settings.captureQuality.title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(AppTheme.softGold)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(AppTheme.panel, in: Capsule())

            TopBarButton(systemName: "gearshape", label: "Настройки") {
                isShowingSettings = true
            }
        }
        .foregroundStyle(.white)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            modeSelector
            lensSelector

            if camera.isManualMode {
                ManualControls(
                    iso: Binding(
                        get: { camera.manualISO },
                        set: camera.setManualISO
                    ),
                    isoRange: camera.isoRange,
                    shutterStops: Binding(
                        get: { camera.shutterStops },
                        set: camera.setManualShutterStops
                    ),
                    shutterRange: camera.shutterStopsRange,
                    focus: Binding(
                        get: { camera.manualFocusPosition },
                        set: camera.setManualFocus
                    ),
                    focusEnabled: camera.isManualFocusSupported
                )
            } else {
                ExposureControl(
                    value: Binding(
                        get: { camera.exposureBias },
                        set: camera.setExposureBias
                    ),
                    range: camera.exposureRange
                )
            }

            presetSelector

            HStack {
                thumbnail
                    .frame(maxWidth: .infinity)

                ShutterButton(isBusy: camera.isCapturing) {
                    if settings.hapticsEnabled {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                    camera.capturePhoto()
                }
                .disabled(!camera.isRunning || camera.isCapturing)
                .frame(maxWidth: .infinity)

                Button(action: camera.switchCamera) {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.system(size: 23, weight: .medium))
                        .frame(width: 48, height: 48)
                        .background(AppTheme.panel, in: Circle())
                }
                .foregroundStyle(.white)
                .accessibilityLabel("Переключить камеру")
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var modeSelector: some View {
        HStack(spacing: 4) {
            ModeButton(title: "AUTO", isSelected: !camera.isManualMode) {
                camera.setManualMode(false)
            }
            ModeButton(title: "PRO", isSelected: camera.isManualMode) {
                camera.setManualMode(true)
            }
        }
        .padding(3)
        .background(AppTheme.panel, in: Capsule())
    }

    private var lensSelector: some View {
        HStack(spacing: 7) {
            ForEach(camera.visibleLenses) { lens in
                Button {
                    camera.selectLens(id: lens.id)
                } label: {
                    Text(lens.shortName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(camera.selectedLensID == lens.id ? .black : .white)
                        .frame(minWidth: 42)
                        .padding(.vertical, 7)
                        .background(
                            camera.selectedLensID == lens.id ? AppTheme.gold : AppTheme.panel,
                            in: Capsule()
                        )
                }
                .accessibilityLabel(lens.name)
            }
        }
        .frame(height: 30)
    }

    private var presetSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(presetStore.presets) { preset in
                    Button {
                        presetStore.selectedPresetID = preset.id
                    } label: {
                        VStack(spacing: 2) {
                            Text(preset.name)
                                .font(.caption2.weight(.bold))
                            if preset.id == PresetModel.lumoraSignature.id {
                                Text("на итоговом фото")
                                    .font(.system(size: 8, weight: .medium))
                                    .opacity(0.7)
                            }
                        }
                        .foregroundStyle(
                            presetStore.selectedPresetID == preset.id ? AppTheme.softGold : .white.opacity(0.64)
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            presetStore.selectedPresetID == preset.id
                                ? AppTheme.gold.opacity(0.14)
                                : Color.clear,
                            in: Capsule()
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 42)
    }

    private var thumbnail: some View {
        Group {
            if let image = camera.lastThumbnail {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(.white.opacity(0.35), lineWidth: 1)
                    }
            } else {
                Image(systemName: "photo")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.48))
                    .frame(width: 48, height: 48)
                    .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 11))
            }
        }
    }

    private var flashIcon: String {
        switch camera.flashMode {
        case .off: return "bolt.slash.fill"
        case .auto: return "bolt.badge.a.fill"
        case .on: return "bolt.fill"
        }
    }
}

private struct ModeButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(isSelected ? .black : .white.opacity(0.62))
                .padding(.horizontal, 16)
                .padding(.vertical, 5)
                .background(isSelected ? AppTheme.gold : Color.clear, in: Capsule())
        }
    }
}

private struct TopBarButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(AppTheme.panel, in: Circle())
        }
        .accessibilityLabel(label)
    }
}

private struct ExposureControl: View {
    @Binding var value: Float
    let range: ClosedRange<Float>

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sun.min")
            Slider(value: $value, in: range)
                .tint(AppTheme.gold)
            Text(String(format: "%+.1f", value))
                .font(.caption.monospacedDigit())
                .frame(width: 38, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(0.72))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Экспокоррекция")
    }
}

private struct ManualControls: View {
    @Binding var iso: Float
    let isoRange: ClosedRange<Float>
    @Binding var shutterStops: Float
    let shutterRange: ClosedRange<Float>
    @Binding var focus: Float
    let focusEnabled: Bool

    var body: some View {
        VStack(spacing: 5) {
            manualSlider(
                title: "ISO",
                value: $iso,
                range: isoRange,
                valueText: String(Int(iso.rounded()))
            )
            manualSlider(
                title: "S",
                value: $shutterStops,
                range: shutterRange,
                valueText: shutterText
            )
            manualSlider(
                title: "F",
                value: $focus,
                range: 0...1,
                valueText: focusEnabled ? String(format: "%.2f", focus) : "AUTO"
            )
            .disabled(!focusEnabled)
            .opacity(focusEnabled ? 1 : 0.45)
        }
    }

    private func manualSlider(
        title: String,
        value: Binding<Float>,
        range: ClosedRange<Float>,
        valueText: String
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(AppTheme.softGold)
                .frame(width: 22)
            Slider(value: value, in: range)
                .tint(AppTheme.gold)
            Text(valueText)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 54, alignment: .trailing)
        }
    }

    private var shutterText: String {
        let seconds = pow(2.0, Double(shutterStops))
        if seconds >= 1 {
            return String(format: "%.1fs", seconds)
        }
        return "1/\(max(1, Int((1 / seconds).rounded())))"
    }
}

private struct ShutterButton: View {
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(.white, lineWidth: 3)
                    .frame(width: 74, height: 74)
                Circle()
                    .fill(isBusy ? AppTheme.gold.opacity(0.45) : .white)
                    .frame(width: 62, height: 62)
                if isBusy {
                    ProgressView()
                        .tint(.black)
                }
            }
        }
        .accessibilityLabel(isBusy ? "Обработка снимка" : "Сделать снимок")
    }
}

private struct RuleOfThirdsGrid: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let width = geometry.size.width
                let height = geometry.size.height
                path.move(to: CGPoint(x: width / 3, y: 0))
                path.addLine(to: CGPoint(x: width / 3, y: height))
                path.move(to: CGPoint(x: width * 2 / 3, y: 0))
                path.addLine(to: CGPoint(x: width * 2 / 3, y: height))
                path.move(to: CGPoint(x: 0, y: height / 3))
                path.addLine(to: CGPoint(x: width, y: height / 3))
                path.move(to: CGPoint(x: 0, y: height * 2 / 3))
                path.addLine(to: CGPoint(x: width, y: height * 2 / 3))
            }
            .stroke(.white.opacity(0.24), lineWidth: 0.6)
        }
    }
}

private struct PermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "camera.fill")
                .font(.system(size: 42))
                .foregroundStyle(AppTheme.gold)
            Text("Нужен доступ к камере")
                .font(.title2.bold())
            Text("LUMORA X обрабатывает снимки локально. Разрешите доступ в Настройках iPhone, чтобы открыть камеру.")
                .font(.body)
                .foregroundStyle(AppTheme.muted)
                .multilineTextAlignment(.center)
            Button("Открыть Настройки") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.gold)
            .foregroundStyle(.black)
        }
        .padding(30)
    }
}

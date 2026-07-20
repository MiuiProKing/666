import Foundation

@MainActor
final class DependencyContainer {
    let settings: AppSettings
    let presetStore: PresetStore
    let cameraEngine: CameraEngine

    init() {
        let settings = AppSettings()
        let presetStore = PresetStore()
        let permissionManager = CameraPermissionManager()
        let photoLibrary = PhotoLibraryService()
        let processor = ImageProcessingPipeline()

        self.settings = settings
        self.presetStore = presetStore
        self.cameraEngine = CameraEngine(
            permissionManager: permissionManager,
            photoLibrary: photoLibrary,
            processor: processor,
            settings: settings,
            presetStore: presetStore
        )
    }
}

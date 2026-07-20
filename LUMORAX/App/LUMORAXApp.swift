import SwiftUI

@main
@MainActor
struct LUMORAXApp: App {
    private let container = DependencyContainer()

    var body: some Scene {
        WindowGroup {
            CameraScreen(
                camera: container.cameraEngine,
                settings: container.settings,
                presetStore: container.presetStore
            )
            .preferredColorScheme(.dark)
        }
    }
}

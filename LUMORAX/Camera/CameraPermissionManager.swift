import AVFoundation

protocol CameraPermissionProviding {
    func currentState() -> CameraAuthorizationState
    func requestAccess() async -> CameraAuthorizationState
}

struct CameraPermissionManager: CameraPermissionProviding {
    func currentState() -> CameraAuthorizationState {
        Self.map(AVCaptureDevice.authorizationStatus(for: .video))
    }

    func requestAccess() async -> CameraAuthorizationState {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        return granted ? .authorized : currentState()
    }

    private static func map(_ status: AVAuthorizationStatus) -> CameraAuthorizationState {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .restricted
        }
    }
}

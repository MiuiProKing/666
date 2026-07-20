import AVFoundation
import Foundation

enum CameraAuthorizationState: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

enum CameraPosition: String, CaseIterable, Identifiable {
    case back
    case front

    var id: String { rawValue }
}

struct CameraLens: Identifiable, Equatable {
    let id: String
    let name: String
    let shortName: String
    let position: CameraPosition
    let deviceType: AVCaptureDevice.DeviceType
}

enum FlashMode: String, CaseIterable, Identifiable {
    case off
    case auto
    case on

    var id: String { rawValue }

    var avMode: AVCaptureDevice.FlashMode {
        switch self {
        case .off: return .off
        case .auto: return .auto
        case .on: return .on
        }
    }
}

enum CameraError: LocalizedError {
    case noCamera
    case cannotCreateInput
    case cannotAddInput
    case cannotAddOutput
    case captureFailed
    case missingPhotoData
    case processingFailed

    var errorDescription: String? {
        switch self {
        case .noCamera: return "Камера на устройстве не найдена."
        case .cannotCreateInput: return "Не удалось открыть выбранную камеру."
        case .cannotAddInput: return "Не удалось подключить камеру к сессии."
        case .cannotAddOutput: return "Не удалось настроить захват фотографии."
        case .captureFailed: return "Снимок не был получен."
        case .missingPhotoData: return "Камера вернула пустой файл снимка."
        case .processingFailed: return "Не удалось обработать снимок."
        }
    }
}

import Foundation
import Photos

enum PhotoLibraryError: LocalizedError {
    case accessDenied
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Нет разрешения на добавление фото в медиатеку."
        case .saveFailed:
            return "Не удалось сохранить фото в медиатеку."
        }
    }
}

protocol PhotoLibrarySaving {
    func savePhoto(data: Data, filename: String) async throws
}

struct PhotoLibraryService: PhotoLibrarySaving {
    func savePhoto(data: Data, filename: String) async throws {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        let status: PHAuthorizationStatus

        if currentStatus == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        } else {
            status = currentStatus
        }

        guard status == .authorized || status == .limited else {
            throw PhotoLibraryError.accessDenied
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = filename
                request.addResource(with: .photo, data: data, options: options)
            }
        } catch {
            throw PhotoLibraryError.saveFailed
        }
    }
}

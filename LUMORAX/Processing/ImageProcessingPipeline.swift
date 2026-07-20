import CoreImage
import Foundation
import Metal
import MetalPetal

protocol ImageProcessing {
    func process(
        photoData: Data,
        preset: PresetModel,
        outputFormat: PhotoOutputFormat
    ) async throws -> Data
}

final class ImageProcessingPipeline: ImageProcessing {
    private let context = CIContext(options: [
        .cacheIntermediates: false,
        .useSoftwareRenderer: false
    ])
    private let queue = DispatchQueue(
        label: "com.yourname.lumorax.processing",
        qos: .userInitiated
    )
    private let metalPetalContext: MTIContext?

    init() {
        if let device = MTLCreateSystemDefaultDevice() {
            metalPetalContext = try? MTIContext(device: device)
        } else {
            metalPetalContext = nil
        }
    }

    func process(
        photoData: Data,
        preset: PresetModel,
        outputFormat: PhotoOutputFormat
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [context, metalPetalContext] in
                do {
                    let result = try Self.render(
                        photoData: photoData,
                        preset: preset,
                        outputFormat: outputFormat,
                        context: context,
                        metalPetalContext: metalPetalContext
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func render(
        photoData: Data,
        preset: PresetModel,
        outputFormat: PhotoOutputFormat,
        context: CIContext,
        metalPetalContext: MTIContext?
    ) throws -> Data {
        guard var image = CIImage(
            data: photoData,
            options: [.applyOrientationProperty: true]
        ) else {
            throw CameraError.processingFailed
        }

        if preset.intensity > 0 {
            if let metalPetalContext,
               let metalOutput = applyingMetalPetal(
                   to: image,
                   preset: preset,
                   context: metalPetalContext
               ) {
                image = metalOutput
            } else {
                image = applyingExposure(to: image, value: preset.exposure * preset.intensity)
                image = applyingColorControls(to: image, preset: preset)
                image = applyingVibrance(to: image, amount: preset.vibrance * preset.intensity)
            }
        }
        image = applyingHighlightShadow(to: image, preset: preset)
        image = applyingTemperature(to: image, preset: preset)
        image = applyingNoiseReduction(to: image, amount: preset.noiseReduction * preset.intensity)
        image = applyingSharpen(to: image, amount: preset.sharpening * preset.intensity)
        image = applyingVignette(to: image, amount: preset.vignette * preset.intensity)

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let options: [CIImageRepresentationOption: Any] = [:]

        let data: Data?
        switch outputFormat {
        case .heif:
            data = context.heifRepresentation(
                of: image,
                format: .RGBA8,
                colorSpace: colorSpace,
                options: options
            )
        case .jpeg:
            data = context.jpegRepresentation(
                of: image,
                colorSpace: colorSpace,
                options: options
            )
        }

        guard let data else { throw CameraError.processingFailed }
        return data
    }

    private static func applyingMetalPetal(
        to image: CIImage,
        preset: PresetModel,
        context: MTIContext
    ) -> CIImage? {
        let exposure = preset.exposure * preset.intensity
        let contrast = 1 + ((preset.contrast - 1) * preset.intensity)
        let saturation = 1 + ((preset.saturation - 1) * preset.intensity)
        let vibrance = preset.vibrance * preset.intensity

        let source = MTIImage(ciImage: image, isOpaque: true)
        let output = source
            .adjusting(exposure: exposure)
            .adjusting(contrast: contrast)
            .adjusting(saturation: saturation)
            .adjusting(vibrance: vibrance)
        return try? context.makeCIImage(from: output)
    }

    private static func applyingExposure(to image: CIImage, value: Float) -> CIImage {
        image.applyingFilter("CIExposureAdjust", parameters: ["inputEV": value])
    }

    private static func applyingColorControls(to image: CIImage, preset: PresetModel) -> CIImage {
        let contrast = 1 + ((preset.contrast - 1) * preset.intensity)
        let saturation = 1 + ((preset.saturation - 1) * preset.intensity)
        return image.applyingFilter("CIColorControls", parameters: [
            "inputContrast": contrast,
            "inputSaturation": saturation
        ])
    }

    private static func applyingHighlightShadow(to image: CIImage, preset: PresetModel) -> CIImage {
        let highlight = 1 + ((preset.highlights - 1) * preset.intensity)
        return image.applyingFilter("CIHighlightShadowAdjust", parameters: [
            "inputHighlightAmount": highlight,
            "inputShadowAmount": preset.shadows * preset.intensity
        ])
    }

    private static func applyingTemperature(to image: CIImage, preset: PresetModel) -> CIImage {
        let neutral = CIVector(x: 6500, y: 0)
        let target = CIVector(
            x: 6500 + CGFloat(preset.temperature * preset.intensity),
            y: CGFloat(preset.tint * preset.intensity)
        )
        return image.applyingFilter("CITemperatureAndTint", parameters: [
            "inputNeutral": neutral,
            "inputTargetNeutral": target
        ])
    }

    private static func applyingVibrance(to image: CIImage, amount: Float) -> CIImage {
        image.applyingFilter("CIVibrance", parameters: ["inputAmount": amount])
    }

    private static func applyingNoiseReduction(to image: CIImage, amount: Float) -> CIImage {
        guard amount > 0 else { return image }
        return image.applyingFilter("CINoiseReduction", parameters: [
            "inputNoiseLevel": min(0.03, amount * 0.035),
            "inputSharpness": 0.35
        ])
    }

    private static func applyingSharpen(to image: CIImage, amount: Float) -> CIImage {
        guard amount > 0 else { return image }
        return image.applyingFilter("CISharpenLuminance", parameters: [
            "inputSharpness": amount,
            "inputRadius": 1.2
        ])
    }

    private static func applyingVignette(to image: CIImage, amount: Float) -> CIImage {
        guard amount > 0 else { return image }
        return image.applyingFilter("CIVignette", parameters: [
            "inputIntensity": amount,
            "inputRadius": 1.2
        ])
    }
}

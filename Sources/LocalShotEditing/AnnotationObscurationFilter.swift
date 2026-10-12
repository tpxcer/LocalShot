import CoreImage
import Foundation

public enum AnnotationObscurationFilter {
    public static func apply(
        to image: CIImage,
        effect: PixelateEffect,
        scale: Double
    ) -> CIImage {
        let extent = image.extent
        let clamped = image.clampedToExtent()
        let filtered: CIImage
        switch effect {
        case .mosaic:
            filtered = clamped.applyingFilter(
                "CIPixellate",
                parameters: [kCIInputScaleKey: max(4, scale)]
            )
        case .blur:
            let radius = max(6, min(48, scale * 0.75))
            filtered = clamped
                .applyingFilter(
                    "CIGaussianBlur",
                    parameters: [kCIInputRadiusKey: radius]
                )
                .applyingFilter(
                    "CIColorControls",
                    parameters: [
                        kCIInputSaturationKey: 1.18,
                        kCIInputContrastKey: 1.03,
                        kCIInputBrightnessKey: 0
                    ]
                )
        }
        return filtered.cropped(to: extent)
    }
}

import CoreGraphics

public enum ScreenCoordinateConverter {
    public static func screenCaptureKitSourceRect(
        fromAppKitSelection selectionRect: CGRect,
        screenHeight: CGFloat
    ) -> CGRect {
        CGRect(
            x: selectionRect.minX,
            y: screenHeight - selectionRect.maxY,
            width: selectionRect.width,
            height: selectionRect.height
        )
    }

    public static func appKitWindowRect(
        fromScreenCaptureKitFrame frame: CGRect,
        primaryScreenHeight: CGFloat
    ) -> CGRect {
        CGRect(
            x: frame.minX,
            y: primaryScreenHeight - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    public static func windowRelativeRect(
        forGlobalSelection selection: CGRect,
        inside windowFrame: CGRect,
        tolerance: CGFloat = 0.5
    ) -> CGRect? {
        let selection = selection.standardized
        let windowFrame = windowFrame.standardized
        guard selection.width >= 4,
              selection.height >= 4,
              windowFrame.width > 0,
              windowFrame.height > 0,
              windowFrame.insetBy(dx: -tolerance, dy: -tolerance).contains(selection) else {
            return nil
        }
        return selection.offsetBy(dx: -windowFrame.minX, dy: -windowFrame.minY)
    }

    public static func pixelCropRect(
        forWindowRelativeRect cropRect: CGRect,
        windowSize: CGSize,
        imageSize: CGSize
    ) -> CGRect? {
        guard windowSize.width > 0,
              windowSize.height > 0,
              imageSize.width > 0,
              imageSize.height > 0 else {
            return nil
        }
        let windowBounds = CGRect(origin: .zero, size: windowSize)
        guard windowBounds.insetBy(dx: -0.5, dy: -0.5).contains(cropRect) else {
            return nil
        }
        let scaleX = imageSize.width / windowSize.width
        let scaleY = imageSize.height / windowSize.height
        let imageBounds = CGRect(origin: .zero, size: imageSize)
        let result = CGRect(
            x: cropRect.minX * scaleX,
            y: cropRect.minY * scaleY,
            width: cropRect.width * scaleX,
            height: cropRect.height * scaleY
        ).integral.intersection(imageBounds)
        guard result.width >= 4, result.height >= 4 else {
            return nil
        }
        return result
    }

    public static func croppedImage(
        _ image: CGImage,
        logicalRect: CGRect,
        logicalSize: CGSize
    ) -> CGImage? {
        guard let pixelRect = pixelCropRect(
            forWindowRelativeRect: logicalRect,
            windowSize: logicalSize,
            imageSize: CGSize(width: image.width, height: image.height)
        ) else {
            return nil
        }
        return image.cropping(to: pixelRect)
    }

    public static func annotationTranslationKeepingScreenPosition(
        from originalSelection: CGRect,
        to resizedSelection: CGRect,
        scaleFactor: CGFloat
    ) -> CGSize {
        CGSize(
            width: (originalSelection.minX - resizedSelection.minX) * scaleFactor,
            height: (originalSelection.minY - resizedSelection.minY) * scaleFactor
        )
    }

    public static func magnifierMappedRect(
        overlayRect: CGRect,
        sourcePixelRect: CGRect,
        viewBounds: CGRect,
        scaleFactor: CGFloat,
        destinationRect: CGRect
    ) -> CGRect? {
        guard !overlayRect.isEmpty,
              sourcePixelRect.width > 0,
              sourcePixelRect.height > 0,
              viewBounds.width > 0,
              viewBounds.height > 0,
              scaleFactor > 0,
              destinationRect.width > 0,
              destinationRect.height > 0 else {
            return nil
        }
        let sourceViewRect = CGRect(
            x: viewBounds.minX + sourcePixelRect.minX / scaleFactor,
            y: viewBounds.maxY - sourcePixelRect.maxY / scaleFactor,
            width: sourcePixelRect.width / scaleFactor,
            height: sourcePixelRect.height / scaleFactor
        )
        let scaleX = destinationRect.width / sourceViewRect.width
        let scaleY = destinationRect.height / sourceViewRect.height
        let overlay = overlayRect.standardized
        return CGRect(
            x: destinationRect.minX + (overlay.minX - sourceViewRect.minX) * scaleX,
            y: destinationRect.minY + (overlay.minY - sourceViewRect.minY) * scaleY,
            width: overlay.width * scaleX,
            height: overlay.height * scaleY
        )
    }
}

import Foundation
import ImageIO
import UIKit

/// Sprint 9 local photo editing (#120). On-device only; nothing here touches the network.
///
/// Every edit starts from an orientation-normalized, downsampled bitmap: ImageIO applies the
/// EXIF orientation (including mirrored front-camera orientations), so crop rectangles are in
/// the same "up" pixel space the user sees. Re-encoding strips source metadata (EXIF, GPS).
enum PhotoEditing {
    /// Matches `UserGarmentPhotoStore.maxStoredPixel`: sources are kept at this bound so
    /// re-editing never compounds loss beyond the first downsample.
    static let sourceMaxPixel = 1600
    static let jpegQuality: CGFloat = 0.82

    /// Decoded, orientation-applied image bounded to `maxPixel` on its long edge.
    static func normalizedImage(from data: Data, maxPixel: Int = sourceMaxPixel) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              CGImageSourceGetCount(source) > 0 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Camera output keeps its orientation in `imageOrientation`; encode with it, then normalize.
    static func normalizedImage(from image: UIImage, maxPixel: Int = sourceMaxPixel) -> CGImage? {
        guard let data = image.jpegData(compressionQuality: 0.95) else { return nil }
        return normalizedImage(from: data, maxPixel: maxPixel)
    }

    static func jpegData(_ image: CGImage, quality: CGFloat = jpegQuality) -> Data? {
        UIImage(cgImage: image).jpegData(compressionQuality: quality)
    }

    /// Crop in normalized pixel space. `rect` comes from `CropGeometry.pixelRect`.
    static func cropped(_ image: CGImage, to rect: CGRect) -> CGImage? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let clipped = rect.integral.intersection(bounds)
        guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1 else { return nil }
        if clipped == bounds { return image }
        return image.cropping(to: clipped)
    }

    static func pixelSize(_ image: CGImage) -> CGSize {
        CGSize(width: image.width, height: image.height)
    }
}

/// What the crop editor hands back. The caller encodes and persists, so each photo type
/// keeps its own storage contract.
struct CropEditResult: Equatable {
    let pixelRect: CGRect
    let aspect: CropGeometry.Aspect
    /// The crop keeps the whole source image.
    let isFullImage: Bool
    /// Save was tapped without moving, zooming or changing shape: keep the current picture
    /// and write nothing.
    let isUntouched: Bool
}

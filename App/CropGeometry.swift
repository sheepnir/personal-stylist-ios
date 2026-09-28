import Foundation

/// Sprint 9 crop editor math (#120). Pure: pixel sizes in, pixel rect out.
///
/// The image is shown aspect-filled inside the crop frame, then scaled by `zoom` (≥ 1) and
/// moved by `offset` (points, image centre relative to the frame centre). The offset is
/// clamped so the image always covers the frame, so every crop is fully inside the image.
enum CropGeometry {
    static let maxZoom: CGFloat = 6

    enum Aspect: String, CaseIterable, Identifiable, Sendable {
        case original
        case portrait4x5
        case square

        var id: String { rawValue }

        /// Width ÷ height for the frame. `original` follows the image.
        func ratio(for imageSize: CGSize) -> CGFloat {
            switch self {
            case .original:
                guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
                return imageSize.width / imageSize.height
            case .portrait4x5:
                return 4.0 / 5.0
            case .square:
                return 1
            }
        }
    }

    /// Largest frame with `ratio` that fits in `available`.
    static func frameSize(ratio: CGFloat, fitting available: CGSize) -> CGSize {
        guard ratio > 0, available.width > 0, available.height > 0 else { return .zero }
        let widthLimited = CGSize(width: available.width, height: available.width / ratio)
        if widthLimited.height <= available.height { return widthLimited }
        return CGSize(width: available.height * ratio, height: available.height)
    }

    /// Points per image pixel at `zoom`.
    static func displayScale(imageSize: CGSize, frame: CGSize, zoom: CGFloat) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 0 }
        let fill = max(frame.width / imageSize.width, frame.height / imageSize.height)
        return fill * clampedZoom(zoom)
    }

    static func clampedZoom(_ zoom: CGFloat) -> CGFloat {
        guard zoom.isFinite else { return 1 }
        return min(max(zoom, 1), maxZoom)
    }

    /// Keep the frame covered: the image edge can never move inside the frame.
    static func clampedOffset(_ offset: CGSize, imageSize: CGSize, frame: CGSize, zoom: CGFloat) -> CGSize {
        let scale = displayScale(imageSize: imageSize, frame: frame, zoom: zoom)
        let maxX = max(0, (imageSize.width * scale - frame.width) / 2)
        let maxY = max(0, (imageSize.height * scale - frame.height) / 2)
        let x = offset.width.isFinite ? offset.width : 0
        let y = offset.height.isFinite ? offset.height : 0
        return CGSize(width: min(max(x, -maxX), maxX), height: min(max(y, -maxY), maxY))
    }

    /// The visible frame in image pixels, integral and inside the image.
    static func pixelRect(imageSize: CGSize, frame: CGSize, zoom: CGFloat, offset: CGSize) -> CGRect {
        let scale = displayScale(imageSize: imageSize, frame: frame, zoom: zoom)
        guard scale > 0 else { return .zero }
        let clamped = clampedOffset(offset, imageSize: imageSize, frame: frame, zoom: zoom)
        let width = frame.width / scale
        let height = frame.height / scale
        let x = imageSize.width / 2 - (frame.width / 2 + clamped.width) / scale
        let y = imageSize.height / 2 - (frame.height / 2 + clamped.height) / scale
        var rect = CGRect(x: x, y: y, width: width, height: height).integral
        rect = rect.intersection(CGRect(origin: .zero, size: imageSize))
        if rect.isNull || rect.width < 1 || rect.height < 1 {
            return CGRect(origin: .zero, size: imageSize)
        }
        return rect
    }

    /// True when the crop keeps the whole image, so Save can skip rewriting files.
    static func isFullImage(_ rect: CGRect, imageSize: CGSize, tolerance: CGFloat = 1) -> Bool {
        abs(rect.minX) <= tolerance
            && abs(rect.minY) <= tolerance
            && abs(rect.width - imageSize.width) <= tolerance
            && abs(rect.height - imageSize.height) <= tolerance
    }
}

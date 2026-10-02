import XCTest
@testable import PersonalStylist

/// Sprint 9 (#120) — crop geometry for portrait, landscape, clamping and no-op detection.
final class CropGeometryTests: XCTestCase {
    private let portrait = CGSize(width: 1200, height: 1600)
    private let landscape = CGSize(width: 1600, height: 900)

    func testSquareFrameOnPortraitCropsCentredFullWidth() {
        let frame = CGSize(width: 300, height: 300)
        let rect = CropGeometry.pixelRect(imageSize: portrait, frame: frame, zoom: 1, offset: .zero)
        XCTAssertEqual(rect, CGRect(x: 0, y: 200, width: 1200, height: 1200))
    }

    func testSquareFrameOnLandscapeCropsCentredFullHeight() {
        let frame = CGSize(width: 300, height: 300)
        let rect = CropGeometry.pixelRect(imageSize: landscape, frame: frame, zoom: 1, offset: .zero)
        XCTAssertEqual(rect, CGRect(x: 350, y: 0, width: 900, height: 900))
    }

    func testOriginalAspectAtRestIsTheFullImage() {
        for size in [portrait, landscape] {
            let ratio = CropGeometry.Aspect.original.ratio(for: size)
            let frame = CropGeometry.frameSize(ratio: ratio, fitting: CGSize(width: 350, height: 500))
            let rect = CropGeometry.pixelRect(imageSize: size, frame: frame, zoom: 1, offset: .zero)
            XCTAssertTrue(CropGeometry.isFullImage(rect, imageSize: size), "\(size) → \(rect)")
        }
    }

    func testZoomHalvesTheCropAroundTheCentre() {
        let frame = CGSize(width: 300, height: 400) // same aspect as the portrait image
        let rect = CropGeometry.pixelRect(imageSize: portrait, frame: frame, zoom: 2, offset: .zero)
        XCTAssertEqual(rect, CGRect(x: 300, y: 400, width: 600, height: 800))
        XCTAssertFalse(CropGeometry.isFullImage(rect, imageSize: portrait))
    }

    func testPanningMovesTheCropOppositeToTheImage() {
        let frame = CGSize(width: 300, height: 400)
        // scale = 0.25 × 2 = 0.5 pt/px; moving the image right by 50 pt shows 100 px further left.
        let rect = CropGeometry.pixelRect(imageSize: portrait, frame: frame, zoom: 2, offset: CGSize(width: 50, height: 0))
        XCTAssertEqual(rect.minX, 200)
        XCTAssertEqual(rect.width, 600)
    }

    func testOffsetIsClampedSoTheFrameStaysCovered() {
        let frame = CGSize(width: 300, height: 300)
        let wild = CGSize(width: 10_000, height: -10_000)
        let clamped = CropGeometry.clampedOffset(wild, imageSize: portrait, frame: frame, zoom: 1)
        XCTAssertEqual(clamped.width, 0, "no horizontal slack at zoom 1 on a portrait square crop")
        XCTAssertEqual(clamped.height, -50, accuracy: 0.001)
        let rect = CropGeometry.pixelRect(imageSize: portrait, frame: frame, zoom: 1, offset: wild)
        XCTAssertEqual(rect, CGRect(x: 0, y: 400, width: 1200, height: 1200))
        XCTAssertTrue(CGRect(origin: .zero, size: portrait).contains(rect))
    }

    func testZoomIsBoundedAndNonFiniteInputIsSafe() {
        XCTAssertEqual(CropGeometry.clampedZoom(0.2), 1)
        XCTAssertEqual(CropGeometry.clampedZoom(50), CropGeometry.maxZoom)
        XCTAssertEqual(CropGeometry.clampedZoom(.nan), 1)
        let frame = CGSize(width: 300, height: 300)
        let rect = CropGeometry.pixelRect(imageSize: portrait, frame: frame, zoom: .infinity,
                                          offset: CGSize(width: CGFloat.nan, height: 0))
        XCTAssertTrue(CGRect(origin: .zero, size: portrait).contains(rect))
        XCTAssertGreaterThanOrEqual(rect.width, 1)
    }

    func testFrameSizeFitsAvailableSpace() {
        XCTAssertEqual(CropGeometry.frameSize(ratio: 1, fitting: CGSize(width: 390, height: 500)), CGSize(width: 390, height: 390))
        XCTAssertEqual(CropGeometry.frameSize(ratio: 0.8, fitting: CGSize(width: 390, height: 300)), CGSize(width: 240, height: 300))
        XCTAssertEqual(CropGeometry.frameSize(ratio: 1, fitting: .zero), .zero)
    }

    func testPositionControlsReachAllEdgesWithoutGestures() {
        let frame = CGSize(width: 300, height: 400)
        for x in [CGFloat(-1), CGFloat(1)] {
            for y in [CGFloat(-1), CGFloat(1)] {
                let offset = CropGeometry.offset(for: CGSize(width: x, height: y),
                                                 imageSize: portrait, frame: frame, zoom: 2)
                let rect = CropGeometry.pixelRect(imageSize: portrait, frame: frame, zoom: 2, offset: offset)
                XCTAssertTrue(CGRect(origin: .zero, size: portrait).contains(rect))
                XCTAssertEqual(x < 0 ? rect.maxX : rect.minX, x < 0 ? portrait.width : 0)
                XCTAssertEqual(y < 0 ? rect.maxY : rect.minY, y < 0 ? portrait.height : 0)
            }
        }
    }

    func testPositionControlsReflectDraggedOffsetAndSaveSameCrop() {
        let frame = CGSize(width: 300, height: 400)
        let dragged = CGSize(width: 57, height: -123)
        let position = CropGeometry.normalizedPosition(dragged, imageSize: portrait, frame: frame, zoom: 3)
        let restored = CropGeometry.offset(for: position, imageSize: portrait, frame: frame, zoom: 3)
        XCTAssertEqual(restored.width, dragged.width, accuracy: 0.001)
        XCTAssertEqual(restored.height, dragged.height, accuracy: 0.001)
        XCTAssertEqual(CropGeometry.pixelRect(imageSize: portrait, frame: frame, zoom: 3, offset: restored),
                       CropGeometry.pixelRect(imageSize: portrait, frame: frame, zoom: 3, offset: dragged))
    }

    func testPositionControlsCannotMoveAnAxisWithNoSlack() {
        let frame = CGSize(width: 300, height: 300)
        let offset = CropGeometry.offset(for: CGSize(width: 1, height: -1),
                                         imageSize: portrait, frame: frame, zoom: 1)
        XCTAssertEqual(offset.width, 0)
        XCTAssertEqual(offset.height, -50)
        XCTAssertEqual(CropGeometry.normalizedPosition(offset, imageSize: portrait, frame: frame, zoom: 1).width, 0)
        let invalid = CropGeometry.offset(for: CGSize(width: CGFloat.nan, height: CGFloat.infinity),
                                          imageSize: portrait, frame: frame, zoom: 2)
        XCTAssertEqual(invalid, .zero)
    }

    func testDegenerateImageFallsBackToFullRect() {
        let rect = CropGeometry.pixelRect(imageSize: .zero, frame: CGSize(width: 10, height: 10), zoom: 1, offset: .zero)
        XCTAssertEqual(rect, .zero)
    }
}

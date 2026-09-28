import XCTest
import ImageIO
import UIKit
import UniformTypeIdentifiers
@testable import PersonalStylist

/// Sprint 9 (#120) — crop persistence for profile and garment reference photos, orientation
/// normalization, and crop-source lifecycle. Synthetic generated images only.
@MainActor
final class PhotoCropTests: XCTestCase {
    private var root: URL!
    private var defaultsSuite: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoCropTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defaultsSuite = "PhotoCropTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuite)
        PhotoReplacePersistHooks.reset()
    }

    override func tearDownWithError() throws {
        PhotoReplacePersistHooks.reset()
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: defaultsSuite)
        try super.tearDownWithError()
    }

    // MARK: - Orientation + crop pixels

    func testNormalizationAppliesRotationAndMirroring() throws {
        // 40×20 image: left half red, right half blue.
        let base = try XCTUnwrap(Self.halves(width: 40, height: 20).cgImage)
        let rotated = try Self.jpeg(base, orientation: .right) // EXIF 6: display is 20×40
        let normalizedRotated = try XCTUnwrap(PhotoEditing.normalizedImage(from: rotated))
        XCTAssertEqual(normalizedRotated.width, 20)
        XCTAssertEqual(normalizedRotated.height, 40)

        let mirrored = try Self.jpeg(base, orientation: .upMirrored) // EXIF 2: horizontal flip
        let normalizedMirrored = try XCTUnwrap(PhotoEditing.normalizedImage(from: mirrored))
        XCTAssertEqual(normalizedMirrored.width, 40)
        let left = try XCTUnwrap(Self.pixel(normalizedMirrored, x: 2, y: 10))
        XCTAssertGreaterThan(left.blue, left.red, "mirrored input shows its right half on the left")
    }

    func testCameraImageOrientationIsNormalized() throws {
        let base = try XCTUnwrap(Self.halves(width: 40, height: 20).cgImage)
        let camera = UIImage(cgImage: base, scale: 1, orientation: .leftMirrored)
        let normalized = try XCTUnwrap(PhotoEditing.normalizedImage(from: camera))
        XCTAssertEqual(normalized.width, 20)
        XCTAssertEqual(normalized.height, 40)
    }

    func testCropUsesNormalizedPixelSpaceAndBoundsOutput() throws {
        let big = UIGraphicsImageRenderer(size: CGSize(width: 3200, height: 2400)).image { ctx in
            UIColor.green.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 3200, height: 2400))
        }
        let data = try XCTUnwrap(big.jpegData(compressionQuality: 0.9))
        let image = try XCTUnwrap(PhotoEditing.normalizedImage(from: data))
        XCTAssertEqual(max(image.width, image.height), PhotoEditing.sourceMaxPixel, "large input is bounded")
        let size = PhotoEditing.pixelSize(image)
        let rect = CropGeometry.pixelRect(imageSize: size, frame: CGSize(width: 300, height: 300), zoom: 1, offset: .zero)
        let cropped = try XCTUnwrap(PhotoEditing.cropped(image, to: rect))
        XCTAssertEqual(cropped.width, cropped.height)
        XCTAssertEqual(cropped.height, image.height)
        XCTAssertTrue(PhotoEditing.cropped(image, to: CGRect(origin: .zero, size: size)) === image)
        XCTAssertNil(PhotoEditing.normalizedImage(from: Data("not an image".utf8)))
    }

    // MARK: - Profile picture

    func testProfileCropKeepsSourceForRecropWithoutReencoding() throws {
        let store = ProfilePhotoStore(directory: root.appendingPathComponent("ProfilePhoto"))
        let picked = try Self.solidJPEG(.red, size: CGSize(width: 1200, height: 900))
        try store.replace(croppedDisplay: try Self.solidJPEG(.red, size: CGSize(width: 900, height: 900)), newSource: picked)
        let source = try XCTUnwrap(try store.loadEditSource())
        let sourceImage = try XCTUnwrap(PhotoEditing.normalizedImage(from: source))
        XCTAssertEqual(sourceImage.width, 1200, "the source keeps the uncropped framing")

        // Re-crop without a new pick: the source bytes are untouched.
        try store.replace(croppedDisplay: try Self.solidJPEG(.red, size: CGSize(width: 500, height: 500)), newSource: nil)
        XCTAssertEqual(try store.loadEditSource(), source)
        let display = try XCTUnwrap(try store.load().flatMap(UIImage.init(data:)))
        XCTAssertLessThanOrEqual(max(display.size.width, display.size.height) * display.scale, 800)

        try store.remove()
        XCTAssertNil(try store.load())
        XCTAssertNil(try store.loadEditSource())
    }

    func testFirstCropOfLegacyPictureKeepsItsPixelsAsSource() throws {
        let folder = root.appendingPathComponent("ProfilePhoto")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let legacy = try Self.solidJPEG(.blue, size: CGSize(width: 800, height: 600))
        try legacy.write(to: folder.appendingPathComponent("profile.jpg"))
        let store = ProfilePhotoStore(directory: folder)
        XCTAssertEqual(try store.loadEditSource(), legacy, "older installs edit from the displayed file")
        try store.replace(croppedDisplay: try Self.solidJPEG(.blue, size: CGSize(width: 600, height: 600)), newSource: nil)
        XCTAssertEqual(try store.loadEditSource(), legacy, "the uncropped legacy picture becomes the source")
    }

    func testInvalidCropKeepsPictureAndSource() throws {
        let store = ProfilePhotoStore(directory: root.appendingPathComponent("ProfilePhoto"))
        try store.replace(with: try Self.solidJPEG(.red, size: CGSize(width: 400, height: 400)))
        let display = try store.load()
        let source = try store.loadEditSource()
        XCTAssertThrowsError(try store.replace(croppedDisplay: Data("bad".utf8), newSource: nil))
        XCTAssertThrowsError(try store.replace(croppedDisplay: try Self.solidJPEG(.red, size: CGSize(width: 10, height: 10)),
                                               newSource: Data("bad".utf8)))
        XCTAssertEqual(try store.load(), display)
        XCTAssertEqual(try store.loadEditSource(), source)
    }

    // MARK: - Garment reference photo

    func testGarmentCropUsesStagedCommitAndKeepsSourceLineage() async throws {
        let (model, store, garment) = try await makeModelWithUserPhoto()
        let originalPath = try XCTUnwrap(garment.imagePath)
        let source = try XCTUnwrap(UserGarmentPhotoStore.editSourceData(forImagePath: originalPath))

        let first = try await model.cropGarmentPhoto(
            garmentId: garment.id,
            croppedJPEG: try Self.solidJPEG(.red, size: CGSize(width: 300, height: 300)),
            editSource: source
        )
        let firstPath = try XCTUnwrap(first.imagePath)
        XCTAssertNotEqual(firstPath, originalPath)
        XCTAssertNil(UserGarmentPhotoStore.resolvedFileURL(originalPath), "the previous display file is removed after commit")
        XCTAssertNotNil(UserGarmentPhotoStore.resolvedFileURL(firstPath))
        XCTAssertEqual(UserGarmentPhotoStore.editSourceData(forImagePath: firstPath), source,
                       "re-editing starts from the retained source, not the crop")
        let persisted = await store.fetchGarments().first { $0.id == garment.id }
        XCTAssertEqual(persisted?.imagePath, firstPath)
        XCTAssertEqual(model.garments.first { $0.id == garment.id }?.imagePath, firstPath)
        XCTAssertEqual(persisted?.purchasePrice, garment.purchasePrice, "crop touches only the photo")

        let second = try await model.cropGarmentPhoto(
            garmentId: garment.id,
            croppedJPEG: try Self.solidJPEG(.red, size: CGSize(width: 200, height: 250)),
            editSource: try XCTUnwrap(UserGarmentPhotoStore.editSourceData(forImagePath: firstPath))
        )
        let secondPath = try XCTUnwrap(second.imagePath)
        XCTAssertEqual(UserGarmentPhotoStore.editSourceData(forImagePath: secondPath), source)
        XCTAssertNil(UserGarmentPhotoStore.resolvedFileURL(firstPath))
        let firstId = try XCTUnwrap(UUID(uuidString: String(firstPath.dropFirst(UserGarmentPhotoStore.pathPrefix.count))))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try UserGarmentPhotoStore.sourceFileURL(forPhotoId: firstId).path),
                       "a replaced display file takes its source with it")
    }

    func testFailedGarmentCropKeepsCurrentPhotoAndLeavesNoSource() async throws {
        let (model, store, garment) = try await makeModelWithUserPhoto()
        let originalPath = try XCTUnwrap(garment.imagePath)
        let source = try XCTUnwrap(UserGarmentPhotoStore.editSourceData(forImagePath: originalPath))
        PhotoReplacePersistHooks.failBeforeMetadataCommit = NSError(domain: "PhotoCropTests", code: 1)
        do {
            try await model.cropGarmentPhoto(
                garmentId: garment.id,
                croppedJPEG: try Self.solidJPEG(.red, size: CGSize(width: 300, height: 300)),
                editSource: source
            )
            XCTFail("expected failure")
        } catch {}
        let staged = try XCTUnwrap(PhotoReplacePersistHooks.lastStagedPath)
        let stagedId = try XCTUnwrap(UUID(uuidString: String(staged.dropFirst(UserGarmentPhotoStore.replacePathPrefix.count))))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try UserGarmentPhotoStore.sourceFileURL(forPhotoId: stagedId).path))
        XCTAssertNil(UserGarmentPhotoStore.resolvedFileURL(staged))
        let persisted = await store.fetchGarments().first { $0.id == garment.id }
        XCTAssertEqual(persisted?.imagePath, originalPath)
        XCTAssertNotNil(UserGarmentPhotoStore.resolvedFileURL(originalPath))
    }

    func testSourceSweepRemovesOnlyOldUnreferencedSources() throws {
        let kept = UUID(), orphan = UUID(), fresh = UUID()
        for id in [kept, orphan, fresh] {
            try UserGarmentPhotoStore.writeSource(try Self.solidJPEG(.gray, size: CGSize(width: 8, height: 8)), forPhotoId: id)
        }
        defer { [kept, orphan, fresh].forEach(UserGarmentPhotoStore.removeSource(forPhotoId:)) }
        let old = Date().addingTimeInterval(-3600)
        for id in [kept, orphan] {
            try FileManager.default.setAttributes([.modificationDate: old],
                                                  ofItemAtPath: try UserGarmentPhotoStore.sourceFileURL(forPhotoId: id).path)
        }
        XCTAssertTrue(UserGarmentPhotoStore.sweepOrphanSources(referencedImagePaths: []).isEmpty,
                      "no references: never delete")
        let removed = UserGarmentPhotoStore.sweepOrphanSources(
            referencedImagePaths: [UserGarmentPhotoStore.userPhotoPath(for: kept), "fixtures/sample.svg"]
        )
        XCTAssertTrue(removed.contains(orphan))
        XCTAssertFalse(removed.contains(kept))
        XCTAssertFalse(removed.contains(fresh), "possibly in-flight crop is kept")
    }

    // MARK: - Helpers

    private func makeModelWithUserPhoto() async throws -> (LoopDemoModel, InMemoryPersistenceStore, StubGarment) {
        var garment = StubGarment(
            id: UUID(), displayName: "Synthetic Crop Shirt", slot: .top, readiness: .ready,
            availability: "AVAILABLE", colorPrimary: nil, pattern: "SOLID", surface: "SMOOTH",
            imagePath: nil, formality: 2, warmth: 2, setId: nil, keepTogether: nil,
            lastWornOn: nil, daysSinceIntake: 0, purchasePrice: 55, purchaseCurrency: "USD"
        )
        garment.imagePath = try UserGarmentPhotoStore.persistJPEG(
            from: try Self.solidJPEG(.orange, size: CGSize(width: 1200, height: 1500)),
            garmentId: garment.id
        )
        addTeardownBlock { [garment] in UserGarmentPhotoStore.removeFiles(forGarmentId: garment.id) }
        let store = InMemoryPersistenceStore(garments: [garment], sets: [], defaults: defaults)
        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()
        return (model, store, garment)
    }

    static func solidJPEG(_ color: UIColor, size: CGSize) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        return try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
    }

    private static func halves(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height))
        }
    }

    private static func jpeg(_ image: CGImage, orientation: CGImagePropertyOrientation) throws -> Data {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation.rawValue] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private static func pixel(_ image: CGImage, x: Int, y: Int) -> (red: Int, blue: Int)? {
        var bytes = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return (Int(bytes[0]), Int(bytes[2]))
    }
}

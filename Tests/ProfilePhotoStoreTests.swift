import XCTest
import UIKit
import ImageIO
import UniformTypeIdentifiers
@testable import PersonalStylist

final class ProfilePhotoStoreTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func image(_ color: UIColor) -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        }.jpegData(compressionQuality: 0.9)!
    }

    func testAddReplaceRelaunchAndRemovePreserveSiblingData() throws {
        let folder = root.appendingPathComponent("ProfilePhoto")
        let wardrobe = root.appendingPathComponent("garment.jpg")
        let profile = root.appendingPathComponent("profile-data.json")
        try Data("wardrobe".utf8).write(to: wardrobe)
        try Data("profile".utf8).write(to: profile)
        let store = ProfilePhotoStore(directory: folder)
        XCTAssertNil(try store.load())
        try store.replace(with: image(.red))
        let first = try XCTUnwrap(store.load())
        XCTAssertNotNil(UIImage(data: first))
        XCTAssertEqual(try ProfilePhotoStore(directory: folder).load(), first)
        try store.replace(with: image(.blue))
        XCTAssertNotEqual(try store.load(), first)
        XCTAssertEqual(try folder.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        try store.remove()
        try store.remove()
        XCTAssertNil(try store.load())
        XCTAssertEqual(try Data(contentsOf: wardrobe), Data("wardrobe".utf8))
        XCTAssertEqual(try Data(contentsOf: profile), Data("profile".utf8))
    }

    func testInvalidReplacementPreservesStoredPicture() throws {
        let store = ProfilePhotoStore(directory: root.appendingPathComponent("ProfilePhoto"))
        try store.replace(with: image(.red))
        let previous = try store.load()
        XCTAssertThrowsError(try store.replace(with: Data("bad image".utf8)))
        XCTAssertEqual(try store.load(), previous)
    }

    func testFailedWriteDoesNotTouchUnrelatedData() throws {
        let file = root.appendingPathComponent("not-a-directory")
        let sentinel = Data("preserve".utf8)
        try sentinel.write(to: file)
        XCTAssertThrowsError(try ProfilePhotoStore(directory: file).replace(with: image(.red)))
        XCTAssertEqual(try Data(contentsOf: file), sentinel)
    }
    func testWriteFailurePreservesExistingPicture() throws {
        let folder = root.appendingPathComponent("ProfilePhoto")
        let store = ProfilePhotoStore(directory: folder)
        try store.replace(with: image(.red))
        let previous = try store.load()
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path) }
        XCTAssertThrowsError(try store.replace(with: image(.blue)))
        XCTAssertEqual(try store.load(), previous)
    }

    func testReencodingBoundsPixelsAndStripsLocationMetadata() throws {
        let original = UIGraphicsImageRenderer(size: CGSize(width: 2000, height: 1000)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2000, height: 1000))
        }
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(original.cgImage), [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 12.34, kCGImagePropertyGPSLongitude: 56.78]
        ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let store = ProfilePhotoStore(directory: root.appendingPathComponent("ProfilePhoto"))
        let saved = try store.replace(with: data as Data)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(saved as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        XCTAssertLessThanOrEqual(properties[kCGImagePropertyPixelWidth] as? Int ?? Int.max, 800)
        XCTAssertLessThanOrEqual(properties[kCGImagePropertyPixelHeight] as? Int ?? Int.max, 800)
        XCTAssertEqual(saved, try store.load())
    }

}

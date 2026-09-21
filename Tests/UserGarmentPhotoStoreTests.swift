import XCTest
import UIKit
@testable import PersonalStylist

final class UserGarmentPhotoStoreTests: XCTestCase {
    func testPersistedJPEGIsCompleteProtectedAndExcludedFromBackup() throws {
        let id = UUID()
        let jpeg = try Self.makeTinyJPEG()
        let path = try UserGarmentPhotoStore.persistJPEG(from: jpeg, garmentId: id)
        XCTAssertTrue(path.hasPrefix(UserGarmentPhotoStore.pathPrefix))

        guard let url = UserGarmentPhotoStore.resolvedFileURL(path) else {
            return XCTFail("expected file URL")
        }

        let values = try url.resourceValues(forKeys: [.fileProtectionKey, .isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)

        // Simulator often does not surface NSFileProtectionComplete in attributes even
        // when setAttributes / Data.WritingOptions.completeFileProtection were applied.
        #if !targetEnvironment(simulator)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let protection = attrs[.protectionKey] as? FileProtectionType
        XCTAssertEqual(protection, .complete)
        XCTAssertEqual(values.fileProtection, .complete)
        #endif

        try? FileManager.default.removeItem(at: url)
    }

    func testReplaceJPEGUsesNewIdAndDoesNotOverwriteGarmentFile() throws {
        let garmentId = UUID()
        let original = try UserGarmentPhotoStore.persistJPEG(from: try Self.makeTinyJPEG(), garmentId: garmentId)
        let originalURL = try XCTUnwrap(UserGarmentPhotoStore.resolvedFileURL(original))

        let stagingId = UUID()
        let staged = try UserGarmentPhotoStore.persistReplaceJPEG(from: try Self.makeTinyJPEG(), stagingId: stagingId)
        XCTAssertTrue(staged.hasPrefix(UserGarmentPhotoStore.replacePathPrefix))
        XCTAssertNotEqual(staged, original)
        XCTAssertTrue(UserGarmentPhotoStore.isOwnedUserFile(staged))
        XCTAssertNotNil(UserGarmentPhotoStore.resolvedFileURL(original))
        XCTAssertNotNil(UserGarmentPhotoStore.resolvedFileURL(staged))
        XCTAssertNotEqual(
            UserGarmentPhotoStore.resolvedFileURL(staged)?.path,
            originalURL.path
        )

        UserGarmentPhotoStore.removeFile(imagePath: staged)
        XCTAssertNotNil(UserGarmentPhotoStore.resolvedFileURL(original))
        UserGarmentPhotoStore.removeFile(imagePath: original)
    }

    func testDeleteOwnedFilesSkipsSharedReferences() throws {
        let ownerId = UUID()
        let peerId = UUID()
        let shared = try UserGarmentPhotoStore.persistJPEG(from: try Self.makeTinyJPEG(), garmentId: ownerId)
        UserGarmentPhotoStore.deleteOwnedFiles(
            for: ownerId,
            additionalPaths: [shared],
            excluding: [shared]
        )
        XCTAssertNotNil(UserGarmentPhotoStore.resolvedFileURL(shared))
        UserGarmentPhotoStore.deleteOwnedFiles(
            for: peerId,
            additionalPaths: [shared],
            excluding: []
        )
        XCTAssertNil(UserGarmentPhotoStore.resolvedFileURL(shared))
    }

    /// 1×1 JPEG that `UIImage(data:)` can decode (Simulator / device).
    private static func makeTinyJPEG() throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let image = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            throw NSError(domain: "UserGarmentPhotoStoreTests", code: 1)
        }
        return data
    }
}

import XCTest
@testable import PersonalStylist

final class PhotoReplaceCopyTests: XCTestCase {
    func testChangePhotoCopyIsExactAndLocal() {
        XCTAssertEqual(PhotoReplaceCopy.changePhoto, "Change photo")
        XCTAssertEqual(PhotoReplaceCopy.chooseFromPhotos, "Choose from Photos")
        XCTAssertEqual(PhotoReplaceCopy.takePhoto, "Take photo")
        XCTAssertEqual(PhotoReplaceCopy.save, "Save")
        XCTAssertEqual(PhotoReplaceCopy.cancel, "Cancel")
        XCTAssertEqual(PhotoReplaceCopy.chooseAnother, "Choose another")
        XCTAssertTrue(PhotoReplaceCopy.changePhotoHint.contains("stays on this iPhone"))
        XCTAssertTrue(PhotoReplaceCopy.staysOnDevice.contains("stays on this iPhone"))
        XCTAssertTrue(PhotoReplaceCopy.deniedMessage.contains("used for the garment locally"))
    }

    func testCopyHasNoMachineTokens() {
        let joined = PhotoReplaceCopy.allUserFacingLines.joined(separator: "\n")
        for forbidden in [
            "HTTP", "http://", "https://", "NSURL", "token",
            "attributeSource", "PendingCapture", "GarmentEntity",
            "replaceGarmentPhoto", "NSPhotoLibrary", "PHPhotoLibrary",
            "TOP", "BOTTOM", "READY", "DRAFT",
        ] {
            XCTAssertFalse(joined.contains(forbidden), "copy must not contain \(forbidden)")
        }
    }

    func testPersistFailureMapsWithoutURLs() {
        XCTAssertEqual(
            PhotoReplaceCopy.persistFailure(from: PhotoReplacePersistError.lowStorage),
            PhotoReplaceCopy.lowStorage
        )
        XCTAssertEqual(
            PhotoReplaceCopy.persistFailure(from: PhotoReplacePersistError.undecodableImage),
            PhotoReplaceCopy.decodeFailed
        )
        XCTAssertEqual(
            PhotoReplaceCopy.persistFailure(from: PhotoReplacePersistError.saveFailed),
            PhotoReplaceCopy.saveFailed
        )
        XCTAssertFalse(PhotoReplaceCopy.lowStorage.contains("http"))
        XCTAssertFalse(PhotoReplaceCopy.saveFailed.contains("URL"))
    }

    func testSliceActionsHaveLabelsAndSaveHint() {
        XCTAssertEqual(PhotoReplaceCopy.changePhoto, "Change photo")
        XCTAssertFalse(PhotoReplaceCopy.changePhotoHint.isEmpty)
        XCTAssertFalse(PhotoReplaceCopy.chooseFromPhotosHint.isEmpty)
        XCTAssertFalse(PhotoReplaceCopy.takePhotoHint.isEmpty)
        XCTAssertFalse(PhotoReplaceCopy.saveHint.isEmpty)
        XCTAssertTrue(PhotoReplaceCopy.saveHint.contains("Save"))
        for line in PhotoReplaceCopy.allUserFacingLines {
            XCTAssertFalse(line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    func testInfoPlistHasNoPhotoLibraryUsageKeys() {
        let info = Bundle(for: LoopDemoModel.self).infoDictionary ?? [:]
        XCTAssertNil(info["NSPhotoLibraryUsageDescription"])
        XCTAssertNil(info["NSPhotoLibraryAddUsageDescription"])
        XCTAssertNotNil(info["NSCameraUsageDescription"])
    }
}

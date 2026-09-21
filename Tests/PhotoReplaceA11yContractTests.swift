import XCTest
@testable import PersonalStylist

/// #280 photo-replace VoiceOver contracts. Spoken strings — not colour alone, no machine tokens.
final class PhotoReplaceA11yContractTests: XCTestCase {
    func testChangePhotoSpeaksDisabledReasonWhileCommitInFlight() {
        XCTAssertEqual(
            PhotoReplaceCopy.changePhotoAccessibilityHint(commitInFlight: false),
            PhotoReplaceCopy.changePhotoHint
        )
        XCTAssertEqual(
            PhotoReplaceCopy.changePhotoAccessibilityHint(commitInFlight: true),
            PhotoReplaceCopy.changePhotoBusy
        )
        XCTAssertTrue(PhotoReplaceCopy.changePhotoBusy.contains("Saving"))
        XCTAssertFalse(PhotoReplaceCopy.containsMachineToken(PhotoReplaceCopy.changePhotoBusy))
    }

    func testPreviewActionsHaveDistinctHintsForNavAndFooterCancel() {
        XCTAssertEqual(PhotoReplaceCopy.saveHint.isEmpty, false)
        XCTAssertEqual(PhotoReplaceCopy.chooseAnotherHint.isEmpty, false)
        XCTAssertNotEqual(PhotoReplaceCopy.chooseAnotherHint, PhotoReplaceCopy.staysOnDevice)
        XCTAssertNotEqual(PhotoReplaceCopy.previewNavCancelHint, PhotoReplaceCopy.previewFooterCancelHint)
        XCTAssertTrue(PhotoReplaceCopy.previewNavCancelHint.localizedCaseInsensitiveContains("preview"))
        XCTAssertTrue(PhotoReplaceCopy.previewFooterCancelHint.localizedCaseInsensitiveContains("original"))
        XCTAssertFalse(PhotoReplaceCopy.containsMachineToken(PhotoReplaceCopy.chooseAnotherHint))
        XCTAssertFalse(PhotoReplaceCopy.containsMachineToken(PhotoReplaceCopy.previewNavCancelHint))
        XCTAssertFalse(PhotoReplaceCopy.containsMachineToken(PhotoReplaceCopy.previewFooterCancelHint))
    }

    func testSuccessAndFailureAnnouncementsStayHuman() {
        XCTAssertEqual(PhotoReplaceCopy.saved, "Photo updated")
        XCTAssertFalse(PhotoReplaceCopy.containsMachineToken(PhotoReplaceCopy.saved))

        let raw = DummyURLError()
        let spoken = PhotoReplaceCopy.failureAnnouncement(from: raw)
        XCTAssertEqual(spoken, PhotoReplaceCopy.captureFailed)
        XCTAssertFalse(spoken.contains("https://"))
        XCTAssertFalse(spoken.contains("NSError"))
        XCTAssertFalse(spoken.contains(raw.description))
        XCTAssertFalse(PhotoReplaceCopy.containsMachineToken(spoken))

        XCTAssertEqual(
            PhotoReplaceCopy.failureAnnouncement(from: PhotoReplacePersistError.saveFailed),
            PhotoReplaceCopy.saveFailed
        )
        XCTAssertEqual(
            PhotoReplaceAlert.persist(PhotoReplaceCopy.saveFailed).message,
            PhotoReplaceCopy.saveFailed
        )
    }

    func testAllPhotoReplaceCopyLinesHaveNoMachineTokens() {
        for line in PhotoReplaceCopy.allUserFacingLines {
            XCTAssertFalse(PhotoReplaceCopy.containsMachineToken(line), line)
        }
    }

    private struct DummyURLError: Error, CustomStringConvertible {
        var description: String { "https://example.invalid/replaceGarmentPhoto NSError" }
    }
}

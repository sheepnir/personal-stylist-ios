import XCTest
@testable import PersonalStylist

final class AppStorageLaunchTests: XCTestCase {
    func testCleanStartFailureDoesNotOpenTheStore() {
        var opened = false
        let launch = AppStorageLaunch.resolve(
            cleanStart: { throw CocoaError(.fileWriteUnknown) },
            openStore: { opened = true }
        )
        XCTAssertEqual(launch, .cleanStartIncomplete)
        XCTAssertFalse(opened)
        XCTAssertEqual(launch.blockedMessage, StorageFailureCopy.cleanStartIncomplete)
    }

    func testStoreOpenFailureDoesNotReportReady() {
        var opened = false
        let launch = AppStorageLaunch.resolve(
            cleanStart: { },
            openStore: {
                opened = true
                throw CocoaError(.fileReadCorruptFile)
            }
        )
        XCTAssertTrue(opened)
        XCTAssertEqual(launch, .wardrobeUnopened)
        XCTAssertEqual(launch.blockedMessage, StorageFailureCopy.wardrobeUnopened)
    }

    func testSuccessOpensTheStore() {
        let launch = AppStorageLaunch.resolve(cleanStart: { }, openStore: { })
        XCTAssertEqual(launch, .ready)
        XCTAssertNil(launch.blockedMessage)
    }
}

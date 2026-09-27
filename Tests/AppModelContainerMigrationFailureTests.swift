import SQLite3
import SwiftData
import XCTest
@testable import PersonalStylist

/// #82 — a migration/open failure that is not the unversioned-store path must not delete the on-disk store.
final class AppModelContainerMigrationFailureTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppModelContainerMigrationFailure-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    @MainActor
    func testNonUnknownOpenFailureLeavesStoreBytesOnDisk() throws {
        let package = root.appendingPathComponent(LegacyStoreFixtureID.mainShapedV1_1.rawValue, isDirectory: true)
        try LegacyStoreFixtures.generate(id: .mainShapedV1_1, at: package)
        let storeURL = LegacyStoreFixtures.storeURL(inPackage: package)

        try dropGarmentTable(at: storeURL)
        let expectedBytes = try Data(contentsOf: storeURL)
        XCTAssertGreaterThan(expectedBytes.count, 64, "need a real legacy store file")

        XCTAssertThrowsError(try AppModelContainer.make(at: storeURL)) { error in
            let ns = error as NSError
            XCTAssertFalse(
                ns.domain == NSCocoaErrorDomain && ns.code == 134504,
                "expected a non-unknown-model-version failure, got \(error)"
            )
            let text = String(describing: error).lowercased()
            XCTAssertFalse(text.contains("unknowndatastoreschema"))
            XCTAssertFalse(text.contains("unknown model version"))
            XCTAssertFalse(text.contains("unknown data store schema"))
            XCTAssertTrue(
                text.contains("migration") || ns.code == 134110,
                "expected a migration/open failure, got \(error)"
            )
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path))
        XCTAssertEqual(try Data(contentsOf: storeURL), expectedBytes)
    }

    private func dropGarmentTable(at storeURL: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open_v2(storeURL.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            throw XCTSkip("sqlite could not open legacy store")
        }
        defer { sqlite3_close(database) }

        guard sqlite3_exec(database, "DROP TABLE ZGARMENTENTITY", nil, nil, nil) == SQLITE_OK else {
            throw XCTSkip("could not drop garment table from legacy store")
        }
    }
}

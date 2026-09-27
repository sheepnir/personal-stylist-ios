import OSLog
import SQLite3
import SwiftData
import XCTest
@testable import PersonalStylist

/// A migration failure other than the unversioned-store path must not delete the store
/// or the records that were still in it. The dropped garment table is the tamper that
/// forces NSCocoaError 134110. It is not evidence about garment rows.
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
    func testMigrationFailureKeepsStoreBytesAndSurvivingRecords() throws {
        let package = root.appendingPathComponent(LegacyStoreFixtureID.mainShapedV1_1.rawValue, isDirectory: true)
        try LegacyStoreFixtures.generate(id: .mainShapedV1_1, at: package)
        let storeURL = LegacyStoreFixtures.storeURL(inPackage: package)

        XCTAssertEqual(try int(storeURL, "SELECT COUNT(*) FROM ZUSERENTITY"), 1)
        XCTAssertEqual(try int(storeURL, "SELECT COUNT(*) FROM ZWEAREVENTENTITY"), 1)
        XCTAssertEqual(try text(storeURL, "SELECT ZSOURCERAW FROM ZWEAREVENTENTITY"), "MANUAL_CONFIRM")
        XCTAssertEqual(try int(storeURL, "SELECT COUNT(*) FROM ZGARMENTENTITY"), 1)

        try dropGarmentTable(at: storeURL)
        let expectedBytes = try Data(contentsOf: storeURL)
        XCTAssertGreaterThan(expectedBytes.count, 64, "need a real legacy store file")
        XCTAssertThrowsError(try tableExists(storeURL, "ZGARMENTENTITY"))

        let openedAt = Date()
        XCTAssertThrowsError(try AppModelContainer.make(at: storeURL)) { error in
            var codes = cocoaErrorCodes(in: error)
            let logged = coreDataLog(since: openedAt)
            if migrationLogContains(logged, code: 134110) {
                codes.append(134110)
            }
            if migrationLogContains(logged, code: 134504) {
                codes.append(134504)
            }
            XCTAssertTrue(
                codes.contains(134110),
                "migration must fail with NSCocoaError 134110, got \(codes)"
            )
            XCTAssertFalse(
                codes.contains(134504),
                "unversioned-store path is a different case, got \(codes)"
            )
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path))
        XCTAssertEqual(try Data(contentsOf: storeURL), expectedBytes)
        XCTAssertEqual(try int(storeURL, "SELECT COUNT(*) FROM ZUSERENTITY"), 1)
        XCTAssertEqual(try int(storeURL, "SELECT COUNT(*) FROM ZWEAREVENTENTITY"), 1)
        XCTAssertEqual(try text(storeURL, "SELECT ZSOURCERAW FROM ZWEAREVENTENTITY"), "MANUAL_CONFIRM")
        XCTAssertThrowsError(try tableExists(storeURL, "ZGARMENTENTITY"))
    }

    /// SwiftData's public description can hide the Core Data code. Read every nested
    /// NSError, then the reflected text, and keep only real Cocoa codes.
    private func cocoaErrorCodes(in error: Error) -> [Int] {
        var codes: [Int] = []
        var seen = Set<ObjectIdentifier>()

        func walk(_ ns: NSError) {
            if seen.contains(ObjectIdentifier(ns)) { return }
            seen.insert(ObjectIdentifier(ns))
            if ns.domain == NSCocoaErrorDomain {
                codes.append(ns.code)
            }
            for value in ns.userInfo.values {
                if let next = value as? NSError {
                    walk(next)
                } else if let next = value as? Error {
                    walk(next as NSError)
                } else if let list = value as? [Any] {
                    for item in list {
                        if let next = item as? NSError {
                            walk(next)
                        } else if let next = item as? Error {
                            walk(next as NSError)
                        }
                    }
                }
            }
        }

        walk(error as NSError)
        let blob = String(reflecting: error) + "\n" + String(describing: error)
        if reflectedCocoaCode(blob, 134110) {
            codes.append(134110)
        }
        if reflectedCocoaCode(blob, 134504) {
            codes.append(134504)
        }
        return codes
    }

    /// Core Data prints 134110 on CI when SwiftData's thrown wrapper hides it.
    /// Accept only that code, written as `Code=134110` or `NSCocoaErrorDomain (134110)`.
    private func coreDataLog(since start: Date) -> String {
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier) else { return "" }
        let position = store.position(date: start.addingTimeInterval(-1))
        guard let entries = try? store.getEntries(at: position) else { return "" }
        return entries.map(\.composedMessage).joined(separator: "\n")
    }

    private func migrationLogContains(_ blob: String, code: Int) -> Bool {
        reflectedCocoaCode(blob, code) || blob.contains("NSCocoaErrorDomain (\(code))")
    }

    /// True when reflected text names this Cocoa code, and not a longer code that shares the digits.
    private func reflectedCocoaCode(_ blob: String, _ code: Int) -> Bool {
        guard blob.contains("NSCocoaErrorDomain") else { return false }
        let needle = "Code=\(code)"
        var search = blob.startIndex
        while let range = blob.range(of: needle, range: search..<blob.endIndex) {
            let after = range.upperBound
            if after == blob.endIndex || !blob[after].isNumber {
                return true
            }
            search = after
        }
        return false
    }

    private func dropGarmentTable(at storeURL: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open_v2(storeURL.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            throw NSError(
                domain: "test",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "sqlite could not open legacy store"]
            )
        }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(database, "DROP TABLE ZGARMENTENTITY", nil, nil, nil) == SQLITE_OK else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "drop failed"
            throw NSError(
                domain: "test",
                code: 7,
                userInfo: [NSLocalizedDescriptionKey: "could not drop garment table: \(message)"]
            )
        }
    }

    private func int(_ storeURL: URL, _ sql: String) throws -> Int {
        try row(storeURL, sql) { Int(sqlite3_column_int($0, 0)) }
    }

    private func text(_ storeURL: URL, _ sql: String) throws -> String {
        try row(storeURL, sql) { statement in
            guard let raw = sqlite3_column_text(statement, 0) else {
                throw NSError(domain: "test", code: 5)
            }
            return String(cString: raw)
        }
    }

    private func tableExists(_ storeURL: URL, _ name: String) throws {
        let count = try int(
            storeURL,
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = '\(name)'"
        )
        if count == 0 {
            throw NSError(domain: "test", code: 1)
        }
    }

    private func row<T>(_ storeURL: URL, _ sql: String, _ read: (OpaquePointer) throws -> T) throws -> T {
        var database: OpaquePointer?
        guard sqlite3_open_v2(storeURL.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            throw NSError(domain: "test", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
        }
        defer { sqlite3_close(database) }
        sqlite3_exec(database, "PRAGMA wal_checkpoint(PASSIVE);", nil, nil, nil)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(database))
            throw NSError(domain: "test", code: 3, userInfo: [NSLocalizedDescriptionKey: "\(message) sql=\(sql)"])
        }
        defer { sqlite3_finalize(statement) }
        guard let statement, sqlite3_step(statement) == SQLITE_ROW else {
            throw NSError(domain: "test", code: 4)
        }
        return try read(statement)
    }
}

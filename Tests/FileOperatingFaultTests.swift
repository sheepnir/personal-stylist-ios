import XCTest
@testable import PersonalStylist

/// Demonstration of injectable file-operation fault seams (#220). Synthetic temp files only.
final class FileOperatingFaultTests: XCTestCase {
    func testWriteFaultPreventsFileCreation() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PSFileFault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let files = FaultInjectingFileOperations()
        files.failNext(.write)
        let url = dir.appendingPathComponent("capture.bin")

        XCTAssertThrowsError(try DurableFileWriter.writeAtomically(Data("x".utf8), to: url, using: files)) { error in
            XCTAssertEqual(error as? FileOperationFault, .writeFailed)
        }
        XCTAssertFalse(files.fileExists(atPath: url.path))
        XCTAssertEqual(files.writeCount, 1)
        XCTAssertEqual(files.synchronizeCount, 0)
    }

    func testSynchronizeFaultLeavesBytesButSignalsDurabilityFailure() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PSFileFault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let files = FaultInjectingFileOperations()
        files.failNext(.synchronize)
        let url = dir.appendingPathComponent("capture.bin")
        let payload = Data("synthetic-only".utf8)

        XCTAssertThrowsError(try DurableFileWriter.writeAtomically(payload, to: url, using: files)) { error in
            XCTAssertEqual(error as? FileOperationFault, .synchronizeFailed)
        }
        XCTAssertTrue(files.fileExists(atPath: url.path))
        XCTAssertEqual(try Data(contentsOf: url), payload)
        XCTAssertEqual(files.synchronizeCount, 1)
    }

    func testDeleteFaultPreservesFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PSFileFault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let files = FaultInjectingFileOperations()
        let url = dir.appendingPathComponent("capture.bin")
        try DurableFileWriter.writeAtomically(Data("keep".utf8), to: url, using: files)

        files.failNext(.delete)
        XCTAssertThrowsError(try files.removeItem(at: url)) { error in
            XCTAssertEqual(error as? FileOperationFault, .deleteFailed)
        }
        XCTAssertTrue(files.fileExists(atPath: url.path))
    }
}

import Foundation

/// Injectable file-system seam for capture / durability fault injection (#220 / M1-ON-QA-06).
/// Production uses `SystemFileOperations`; tests swap in `FaultInjectingFileOperations`.
protocol FileOperating: Sendable {
    func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]?
    ) throws

    func write(_ data: Data, to url: URL, options: Data.WritingOptions) throws

    /// Durability step (fsync / synchronize) after a successful write.
    func synchronize(fileAt url: URL) throws

    func removeItem(at url: URL) throws

    func fileExists(atPath path: String) -> Bool
}

enum FileOperationFault: Error, Equatable {
    case writeFailed
    case synchronizeFailed
    case deleteFailed
}

/// Real `FileManager` / `Data` / `FileHandle` implementation.
struct SystemFileOperations: FileOperating {
    func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]?
    ) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: createIntermediates,
            attributes: attributes
        )
    }

    func write(_ data: Data, to url: URL, options: Data.WritingOptions) throws {
        try data.write(to: url, options: options)
    }

    func synchronize(fileAt url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.synchronize()
    }

    func removeItem(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
}

/// Test double that can fail the next write, synchronize, or delete.
final class FaultInjectingFileOperations: FileOperating, @unchecked Sendable {
    enum Step: Equatable {
        case write
        case synchronize
        case delete
    }

    private let lock = NSLock()
    private let inner: FileOperating
    private var failNext: Step?
    private(set) var writeCount = 0
    private(set) var synchronizeCount = 0
    private(set) var deleteCount = 0

    init(inner: FileOperating = SystemFileOperations()) {
        self.inner = inner
    }

    func failNext(_ step: Step) {
        lock.lock()
        failNext = step
        lock.unlock()
    }

    func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]?
    ) throws {
        try inner.createDirectory(
            at: url,
            withIntermediateDirectories: createIntermediates,
            attributes: attributes
        )
    }

    func write(_ data: Data, to url: URL, options: Data.WritingOptions) throws {
        lock.lock()
        writeCount += 1
        let shouldFail = failNext == .write
        if shouldFail { failNext = nil }
        lock.unlock()
        if shouldFail { throw FileOperationFault.writeFailed }
        try inner.write(data, to: url, options: options)
    }

    func synchronize(fileAt url: URL) throws {
        lock.lock()
        synchronizeCount += 1
        let shouldFail = failNext == .synchronize
        if shouldFail { failNext = nil }
        lock.unlock()
        if shouldFail { throw FileOperationFault.synchronizeFailed }
        try inner.synchronize(fileAt: url)
    }

    func removeItem(at url: URL) throws {
        lock.lock()
        deleteCount += 1
        let shouldFail = failNext == .delete
        if shouldFail { failNext = nil }
        lock.unlock()
        if shouldFail { throw FileOperationFault.deleteFailed }
        try inner.removeItem(at: url)
    }

    func fileExists(atPath path: String) -> Bool {
        inner.fileExists(atPath: path)
    }
}

/// Tiny durable write helper used by #220 demonstration tests (and later capture work).
enum DurableFileWriter {
    static func writeAtomically(
        _ data: Data,
        to url: URL,
        using files: FileOperating,
        options: Data.WritingOptions = [.atomic]
    ) throws {
        try files.write(data, to: url, options: options)
        try files.synchronize(fileAt: url)
    }
}

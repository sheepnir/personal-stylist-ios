import XCTest
import UIKit
@testable import PersonalStylist

/// Sprint 9 (#121, #122) — gallery session: local save first, separate Photos outcome,
/// no duplicate items or exports, and no effect on wear or garment data.
@MainActor
final class WearingGallerySessionTests: XCTestCase {
    private var defaultsSuite: String!
    private var defaults: UserDefaults!
    private var fileStore: WearingPhotoFileStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaultsSuite = "WearingGallerySessionTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuite)
        fileStore = .temporary()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fileStore.directory)
        defaults.removePersistentDomain(forName: defaultsSuite)
        try super.tearDownWithError()
    }

    func testLatestFirstWithFivePreviewsAndAllKept() async throws {
        let (session, _, garment) = try await makeSession()
        let base = Date(timeIntervalSince1970: 1_760_000_000)
        for offset in 0..<8 {
            _ = await session.add(request(garment.id, source: .library, at: base.addingTimeInterval(Double(offset))))
        }
        XCTAssertEqual(session.photos.count, 8)
        XCTAssertEqual(session.latest?.addedAt, base.addingTimeInterval(7))
        XCTAssertEqual(session.recentPreviews.count, WearingPhotoOrdering.recentLimit)
        XCTAssertEqual(session.recentPreviews.first?.addedAt, base.addingTimeInterval(6))
    }

    func testRepeatedSaveTapsCreateOneItem() async throws {
        let (session, _, garment) = try await makeSession()
        let req = request(garment.id, source: .camera)
        async let first = session.add(req)
        async let second = session.add(req)
        _ = await (first, second)
        _ = await session.add(req) // retry after completion: idempotent
        XCTAssertEqual(session.photos.count, 1)
    }

    func testExportSuccessRecordsSavedAndExportsTheConfirmedPicture() async throws {
        let exporter = FakeExporter(outcomes: [.saved])
        let (session, _, garment) = try await makeSession(exporter: exporter)
        let req = request(garment.id, source: .camera)
        let added1 = await session.add(req)
        let photo = try XCTUnwrap(added1)
        let outcome = await session.exportToPhotos(photo)
        XCTAssertEqual(outcome, .saved)
        XCTAssertEqual(exporter.saved, [req.displayJPEG], "the exported bytes are the confirmed display picture")
        XCTAssertEqual(session.photos.first?.exportState, .saved)
        XCTAssertEqual(session.message, WearingGalleryCopy.exportMessage(.saved))
    }

    func testDeniedExportKeepsLocalPhotoAndRetryDoesNotDuplicate() async throws {
        let exporter = FakeExporter(outcomes: [.denied, .failed, .saved])
        let (session, _, garment) = try await makeSession(exporter: exporter)
        let added2 = await session.add(request(garment.id, source: .camera))
        let photo = try XCTUnwrap(added2)

        let result3 = await session.exportToPhotos(photo)
        XCTAssertEqual(result3, .denied)
        XCTAssertEqual(session.photos.count, 1, "local save survives a denied export")
        XCTAssertEqual(session.photos.first?.exportState, .failed)
        XCTAssertNotEqual(session.message, WearingGalleryCopy.exportMessage(.saved), "never claims Saved to Photos")
        XCTAssertEqual(session.exportOutcomes[photo.id], .denied, "Settings is offered only for a known denial")

        let result4 = await session.exportToPhotos(photo)
        XCTAssertEqual(result4, .failed)
        let result5 = await session.exportToPhotos(photo)
        XCTAssertEqual(result5, .saved)
        XCTAssertEqual(session.photos.count, 1, "export retries never add a gallery item")
        XCTAssertEqual(session.photos.first?.exportState, .saved)
        XCTAssertEqual(exporter.saved.count, 3)
        XCTAssertEqual(session.exportOutcomes[photo.id], .saved)
    }

    func testMissingDisplayFileRecordsAFailedExportWithoutCallingPhotos() async throws {
        let exporter = FakeExporter(outcomes: [.saved])
        let (session, _, garment) = try await makeSession(exporter: exporter)
        let added = await session.add(request(garment.id, source: .camera))
        let photo = try XCTUnwrap(added)
        try FileManager.default.removeItem(at: fileStore.fileURL(for: photo.displayFileId))
        let outcome = await session.exportToPhotos(photo)
        XCTAssertEqual(outcome, .failed)
        XCTAssertTrue(exporter.saved.isEmpty)
        XCTAssertEqual(session.photos.first?.exportState, .failed, "recorded, so the viewer offers Retry")
        XCTAssertNotEqual(session.message, WearingGalleryCopy.exportMessage(.saved))
    }

    func testConcurrentExportTapsExportOnce() async throws {
        let exporter = FakeExporter(outcomes: [.saved, .saved], delayNanoseconds: 200_000_000)
        let (session, _, garment) = try await makeSession(exporter: exporter)
        let added6 = await session.add(request(garment.id, source: .camera))
        let photo = try XCTUnwrap(added6)
        async let a = session.exportToPhotos(photo)
        async let b = session.exportToPhotos(photo)
        let results = await [a, b]
        XCTAssertEqual(exporter.saved.count, 1)
        XCTAssertEqual(results.compactMap { $0 }, [.saved])
    }

    func testLibraryImportsAreNeverExported() async throws {
        let exporter = FakeExporter(outcomes: [.saved])
        let (session, _, garment) = try await makeSession(exporter: exporter)
        let added7 = await session.add(request(garment.id, source: .library))
        let photo = try XCTUnwrap(added7)
        let result8 = await session.exportToPhotos(photo)
        XCTAssertNil(result8)
        XCTAssertTrue(exporter.saved.isEmpty)
    }

    func testCropKeepsOrderAndRemoveKeepsEverythingElse() async throws {
        let (session, store, garment) = try await makeSession()
        try await store.saveWearEvent(StubWearEvent(id: UUID(), garmentIds: [garment.id], wornOn: Date()))
        let aggregatesBefore = await store.fetchWearAggregates()
        let base = Date(timeIntervalSince1970: 1_760_000_000)
        let added9 = await session.add(request(garment.id, source: .library, at: base))
        let older = try XCTUnwrap(added9)
        let added10 = await session.add(request(garment.id, source: .library, at: base.addingTimeInterval(10)))
        let newer = try XCTUnwrap(added10)

        let cropped = await session.updateCrop(of: older, displayJPEG: try Self.jpeg(.green))
        XCTAssertTrue(cropped)
        XCTAssertEqual(session.photos.map(\.id), [newer.id, older.id])

        await session.remove(newer)
        XCTAssertEqual(session.photos.map(\.id), [older.id])
        XCTAssertEqual(session.message, WearingGalleryCopy.removed)
        let aggregatesAfter = await store.fetchWearAggregates()
        XCTAssertEqual(aggregatesAfter, aggregatesBefore, "gallery actions never change wear counts")
        let garments = await store.fetchGarments()
        XCTAssertEqual(garments.first?.imagePath, "fixtures/synthetic-reference.svg", "reference photo untouched")
        XCTAssertNotNil(session.editSourceImage(for: try XCTUnwrap(session.photos.first)))
    }

    func testSaveForDeletedGarmentShowsMessageAndAddsNothing() async throws {
        let (session, store, garment) = try await makeSession()
        try await store.deleteGarment(id: garment.id)
        let result = await session.add(request(garment.id, source: .camera))
        XCTAssertNil(result)
        XCTAssertEqual(session.message, WearingGalleryCopy.saveFailure(.garmentUnavailable))
        XCTAssertTrue(session.photos.isEmpty)
    }

    // MARK: - Helpers

    private final class FakeExporter: PhotoLibraryExporting, @unchecked Sendable {
        private let lock = NSLock()
        private var outcomes: [PhotoLibraryExportOutcome]
        private var savedData: [Data] = []
        private let delayNanoseconds: UInt64

        init(outcomes: [PhotoLibraryExportOutcome], delayNanoseconds: UInt64 = 0) {
            self.outcomes = outcomes
            self.delayNanoseconds = delayNanoseconds
        }

        var saved: [Data] {
            lock.lock(); defer { lock.unlock() }
            return savedData
        }

        func saveToPhotos(_ jpeg: Data) async -> PhotoLibraryExportOutcome {
            if delayNanoseconds > 0 { try? await Task.sleep(nanoseconds: delayNanoseconds) }
            lock.lock(); defer { lock.unlock() }
            savedData.append(jpeg)
            return outcomes.isEmpty ? .saved : outcomes.removeFirst()
        }
    }

    private func makeSession(
        exporter: FakeExporter = FakeExporter(outcomes: [])
    ) async throws -> (WearingGallerySession, InMemoryPersistenceStore, StubGarment) {
        let garment = StubGarment(
            id: UUID(), displayName: "Synthetic Gallery Jacket", slot: .jacket, readiness: .ready,
            availability: "AVAILABLE", colorPrimary: nil, pattern: "SOLID", surface: "SMOOTH",
            imagePath: "fixtures/synthetic-reference.svg", formality: 2, warmth: 3, setId: nil, keepTogether: nil,
            lastWornOn: nil, daysSinceIntake: 0
        )
        let store = InMemoryPersistenceStore(garments: [garment], sets: [], defaults: defaults, wearingPhotoFiles: fileStore)
        let session = WearingGallerySession(garmentId: garment.id, store: store, exporter: exporter)
        await session.load()
        return (session, store, garment)
    }

    private func request(_ garmentId: UUID, source: WearingPhotoSource, at date: Date = Date()) -> WearingPhotoAddRequest {
        WearingPhotoAddRequest(
            garmentId: garmentId,
            displayJPEG: (try? Self.jpeg(.red)) ?? Data(),
            sourceJPEG: (try? Self.jpeg(.blue)) ?? Data(),
            source: source,
            addedAt: date
        )
    }

    static func jpeg(_ color: UIColor) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4), format: format).image { ctx in
            color.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        return try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
    }
}

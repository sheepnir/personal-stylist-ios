import XCTest
import SwiftData
import UIKit
@testable import PersonalStylist

/// Sprint 9 (#119, ADR-0004) — wearing-gallery persistence on both stores.
/// Synthetic 1×1 JPEGs and temporary directories only.
final class WearingPhotoPersistTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!
    private var fileStores: [WearingPhotoFileStore] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaultsSuiteName = "WearingPhotoPersistTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        WearingPhotoPersistHooks.reset()
    }

    override func tearDownWithError() throws {
        WearingPhotoPersistHooks.reset()
        for store in fileStores {
            try? FileManager.default.removeItem(at: store.directory)
        }
        fileStores = []
        if let defaultsSuiteName {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }
        defaults = nil
        defaultsSuiteName = nil
        try super.tearDownWithError()
    }

    // MARK: - Ordering, idempotency, retention (both stores)

    @MainActor
    func testNewestFirstWithStableTieBreakAndNoFiveLimit() async throws {
        for store in try makeStores() {
            let garment = try await seedGarment(in: store)
            let base = Date(timeIntervalSince1970: 1_760_000_000)
            var added: [StubWearingPhoto] = []
            for offset in 0..<7 {
                added.append(try await store.addWearingPhoto(request(garment.id, at: base.addingTimeInterval(Double(offset)))))
            }
            let tieA = try await store.addWearingPhoto(request(garment.id, at: base.addingTimeInterval(100)))
            let tieB = try await store.addWearingPhoto(request(garment.id, at: base.addingTimeInterval(100)))

            let fetched = await store.fetchWearingPhotos(garmentId: garment.id)
            XCTAssertEqual(fetched.count, 9, "\(store.backendName): the sixth and older photos are kept")
            let ties = [tieA, tieB].sorted { $0.id.uuidString < $1.id.uuidString }
            XCTAssertEqual(Array(fetched.prefix(2)).map(\.id), ties.map(\.id))
            XCTAssertEqual(Array(fetched.dropFirst(2)).map(\.id), added.reversed().map(\.id))
            let again = await store.fetchWearingPhotos(garmentId: garment.id)
            XCTAssertEqual(again.map(\.id), fetched.map(\.id), "order is stable across fetches")
        }
    }

    @MainActor
    func testRetriedAddWithSameIdCreatesNoDuplicateOrExtraFiles() async throws {
        for store in try makeStores() {
            let garment = try await seedGarment(in: store)
            let req = request(garment.id)
            let first = try await store.addWearingPhoto(req)
            let filesAfterFirst = jpegCount(store.wearingPhotoFiles)
            let second = try await store.addWearingPhoto(req)
            XCTAssertEqual(first, second)
            let fetched = await store.fetchWearingPhotos(garmentId: garment.id)
            XCTAssertEqual(fetched.count, 1, store.backendName)
            XCTAssertEqual(jpegCount(store.wearingPhotoFiles), filesAfterFirst)
            XCTAssertEqual(filesAfterFirst, 2, "display + source")
        }
    }

    @MainActor
    func testConcurrentRepeatedSavesCreateOneAssociation() async throws {
        for store in try makeStores() {
            let garment = try await seedGarment(in: store)
            let req = request(garment.id)
            async let a = store.addWearingPhoto(req)
            async let b = store.addWearingPhoto(req)
            async let c = store.addWearingPhoto(req)
            _ = try await [a, b, c]
            let fetched = await store.fetchWearingPhotos(garmentId: garment.id)
            XCTAssertEqual(fetched.count, 1, store.backendName)
            XCTAssertEqual(jpegCount(store.wearingPhotoFiles), 2, store.backendName)
        }
    }

    // MARK: - Failure leaves no trace

    @MainActor
    func testAddForMissingGarmentIsRejectedAndLeavesNoFiles() async throws {
        for store in try makeStores() {
            _ = try await seedGarment(in: store)
            let missing = UUID()
            do {
                _ = try await store.addWearingPhoto(request(missing))
                XCTFail("expected garmentUnavailable")
            } catch {
                XCTAssertEqual(error as? WearingPhotoPersistError, .garmentUnavailable)
            }
            XCTAssertEqual(jpegCount(store.wearingPhotoFiles), 0, store.backendName)
        }
    }

    @MainActor
    func testFailureBeforeCommitLeavesNoRowAndNoFiles() async throws {
        for store in try makeStores() {
            let garment = try await seedGarment(in: store)
            WearingPhotoPersistHooks.failBeforeMetadataCommit = NSError(domain: "test", code: 1)
            do {
                _ = try await store.addWearingPhoto(request(garment.id))
                XCTFail("expected failure")
            } catch {
                XCTAssertEqual(error as? WearingPhotoPersistError, .saveFailed)
            }
            let fetched = await store.fetchWearingPhotos(garmentId: garment.id)
            XCTAssertTrue(fetched.isEmpty, store.backendName)
            XCTAssertEqual(jpegCount(store.wearingPhotoFiles), 0, store.backendName)
        }
    }

    @MainActor
    func testFileWriteFailureLeavesNoRow() async throws {
        let faults = FaultInjectingFileOperations()
        let files = trackedFileStore(files: faults)
        let store = InMemoryPersistenceStore(garments: [], defaults: defaults, wearingPhotoFiles: files)
        let garment = try await seedGarment(in: store)
        faults.failNext(.write)
        do {
            _ = try await store.addWearingPhoto(request(garment.id))
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error as? WearingPhotoPersistError, .saveFailed)
        }
        let fetched = await store.fetchWearingPhotos(garmentId: garment.id)
        XCTAssertTrue(fetched.isEmpty)
        XCTAssertEqual(jpegCount(files), 0)

        // A failed durability step (fsync) also leaves no file and no row.
        let photoCountBefore = jpegCount(files)
        faults.failNext(.synchronize)
        _ = try? await store.addWearingPhoto(request(garment.id))
        XCTAssertEqual(jpegCount(files), photoCountBefore)
    }

    // MARK: - Edit keeps order and source

    @MainActor
    func testCropUpdateKeepsAddedAtAndSourceAndRemovesOldDisplay() async throws {
        for store in try makeStores() {
            let garment = try await seedGarment(in: store)
            let addedAt = Date(timeIntervalSince1970: 1_760_000_000)
            let older = try await store.addWearingPhoto(request(garment.id, at: addedAt))
            let newer = try await store.addWearingPhoto(request(garment.id, at: addedAt.addingTimeInterval(60)))

            let edited = try await store.updateWearingPhotoDisplay(id: older.id, displayJPEG: try Self.jpeg(.green))
            XCTAssertEqual(edited.addedAt, addedAt, store.backendName)
            XCTAssertEqual(edited.sourceFileId, older.sourceFileId)
            XCTAssertNotEqual(edited.displayFileId, older.displayFileId)
            XCTAssertTrue(store.wearingPhotoFiles.exists(edited.displayFileId))
            XCTAssertFalse(store.wearingPhotoFiles.exists(older.displayFileId))
            XCTAssertTrue(store.wearingPhotoFiles.exists(try XCTUnwrap(older.sourceFileId)))

            let fetched = await store.fetchWearingPhotos(garmentId: garment.id)
            XCTAssertEqual(fetched.map(\.id), [newer.id, older.id], "editing does not make a photo newly added")
        }
    }

    @MainActor
    func testFailedCropUpdateKeepsPreviousDisplay() async throws {
        for store in try makeStores() {
            let garment = try await seedGarment(in: store)
            let photo = try await store.addWearingPhoto(request(garment.id))
            let before = jpegCount(store.wearingPhotoFiles)
            WearingPhotoPersistHooks.failBeforeMetadataCommit = NSError(domain: "test", code: 2)
            _ = try? await store.updateWearingPhotoDisplay(id: photo.id, displayJPEG: try Self.jpeg(.green))
            let fetched = await store.fetchWearingPhotos(garmentId: garment.id)
            XCTAssertEqual(fetched.first?.displayFileId, photo.displayFileId, store.backendName)
            XCTAssertTrue(store.wearingPhotoFiles.exists(photo.displayFileId))
            XCTAssertEqual(jpegCount(store.wearingPhotoFiles), before)
        }
    }

    @MainActor
    func testCropUpdateWithoutRetainedSourceKeepsPreEditPixelsAsSource() async throws {
        for store in try makeStores() {
            let garment = try await seedGarment(in: store)
            var req = request(garment.id)
            req.sourceJPEG = nil
            let photo = try await store.addWearingPhoto(req)
            XCTAssertNil(photo.sourceFileId)
            let edited = try await store.updateWearingPhotoDisplay(id: photo.id, displayJPEG: try Self.jpeg(.green))
            XCTAssertEqual(edited.sourceFileId, photo.displayFileId, store.backendName)
            XCTAssertTrue(store.wearingPhotoFiles.exists(photo.displayFileId))
        }
    }

    // MARK: - Removal scope

    @MainActor
    func testRemoveTouchesOnlyThatPhoto() async throws {
        for store in try makeStores() {
            let garment = try await seedGarment(in: store)
            let other = try await seedGarment(in: store, name: "Synthetic Linen Shirt")
            try await store.saveWearEvent(
                StubWearEvent(id: UUID(), garmentIds: [garment.id], wornOn: Date(timeIntervalSince1970: 1_760_000_000))
            )
            let countsBefore = await store.fetchWearAggregates()
            let keep = try await store.addWearingPhoto(request(garment.id))
            let remove = try await store.addWearingPhoto(request(garment.id))
            let otherPhoto = try await store.addWearingPhoto(request(other.id))

            try await store.removeWearingPhoto(id: remove.id)
            try await store.removeWearingPhoto(id: remove.id) // missing id: no-op

            let remaining = await store.fetchWearingPhotos(garmentId: garment.id)
            XCTAssertEqual(remaining.map(\.id), [keep.id], store.backendName)
            XCTAssertFalse(store.wearingPhotoFiles.exists(remove.displayFileId))
            XCTAssertFalse(store.wearingPhotoFiles.exists(try XCTUnwrap(remove.sourceFileId)))
            XCTAssertTrue(store.wearingPhotoFiles.exists(keep.displayFileId))
            XCTAssertTrue(store.wearingPhotoFiles.exists(otherPhoto.displayFileId))
            let garments = await store.fetchGarments()
            XCTAssertEqual(garments.first { $0.id == garment.id }?.imagePath, garment.imagePath)
            let countsAfter = await store.fetchWearAggregates()
            XCTAssertEqual(countsAfter, countsBefore, "photos never change wear counts")
        }
    }

    @MainActor
    func testGarmentDeleteRemovesOnlyItsGallery() async throws {
        for store in try makeStores() {
            let doomed = try await seedGarment(in: store)
            let kept = try await seedGarment(in: store, name: "Synthetic Wool Jumper")
            let doomedPhoto = try await store.addWearingPhoto(request(doomed.id))
            let keptPhoto = try await store.addWearingPhoto(request(kept.id))

            try await store.deleteGarment(id: doomed.id)

            let doomedAfter = await store.fetchWearingPhotos(garmentId: doomed.id)
            XCTAssertTrue(doomedAfter.isEmpty, store.backendName)
            XCTAssertFalse(store.wearingPhotoFiles.exists(doomedPhoto.displayFileId))
            let keptAfter = await store.fetchWearingPhotos(garmentId: kept.id)
            XCTAssertEqual(keptAfter.map(\.id), [keptPhoto.id])
            XCTAssertTrue(store.wearingPhotoFiles.exists(keptPhoto.displayFileId))
        }
    }

    @MainActor
    func testClearWardrobeRemovesEveryGalleryRowAndFile() async throws {
        for store in try makeStores() {
            let garment = try await seedGarment(in: store)
            _ = try await store.addWearingPhoto(request(garment.id))
            try await store.clearWardrobeAndLooks()
            let after = await store.fetchWearingPhotos(garmentId: garment.id)
            XCTAssertTrue(after.isEmpty, store.backendName)
            XCTAssertEqual(jpegCount(store.wearingPhotoFiles), 0)
        }
    }

    @MainActor
    func testSaveAfterGarmentDeletedIsRejectedAndCleansOnlyItsFiles() async throws {
        for store in try makeStores() {
            let garment = try await seedGarment(in: store)
            let other = try await seedGarment(in: store, name: "Synthetic Denim Jacket")
            let otherPhoto = try await store.addWearingPhoto(request(other.id))
            try await store.deleteGarment(id: garment.id)
            do {
                _ = try await store.addWearingPhoto(request(garment.id))
                XCTFail("expected garmentUnavailable")
            } catch {
                XCTAssertEqual(error as? WearingPhotoPersistError, .garmentUnavailable)
            }
            XCTAssertEqual(jpegCount(store.wearingPhotoFiles), 2, "only the other garment's files remain")
            XCTAssertTrue(store.wearingPhotoFiles.exists(otherPhoto.displayFileId))
        }
    }

    // MARK: - Export state

    @MainActor
    func testExportStateIsRecordedWithoutNewGalleryItem() async throws {
        for store in try makeStores() {
            let garment = try await seedGarment(in: store)
            var req = request(garment.id)
            req.source = .camera
            let photo = try await store.addWearingPhoto(req)
            XCTAssertNil(photo.exportState)
            _ = try await store.setWearingPhotoExportState(id: photo.id, state: .failed)
            let retried = try await store.setWearingPhotoExportState(id: photo.id, state: .saved)
            XCTAssertEqual(retried.exportState, .saved)
            let fetched = await store.fetchWearingPhotos(garmentId: garment.id)
            XCTAssertEqual(fetched.count, 1, store.backendName)
            XCTAssertEqual(fetched.first?.source, .camera)

            let imported = try await store.addWearingPhoto(request(garment.id))
            do {
                _ = try await store.setWearingPhotoExportState(id: imported.id, state: .saved)
                XCTFail("library imports are never exported")
            } catch {
                XCTAssertEqual(error as? WearingPhotoPersistError, .photoUnavailable)
            }
        }
    }

    // MARK: - Relaunch + orphan sweep

    @MainActor
    func testGalleryRowsAndFilesSurviveRelaunch() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PSTestStore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("PersonalStylistLocal.store")
        let files = trackedFileStore()

        let garment: StubGarment
        let photo: StubWearingPhoto
        do {
            // First launch: every reference to the container ends with this scope.
            let store = SwiftDataPersistenceStore(
                container: try TestModelContainers.makeOnDisk(storeURL: storeURL),
                defaults: defaults,
                wearingPhotoFiles: files
            )
            garment = try await seedGarment(in: store)
            photo = try await store.addWearingPhoto(request(garment.id))
        }

        let relaunched = SwiftDataPersistenceStore(
            container: try TestModelContainers.makeOnDisk(storeURL: storeURL),
            defaults: defaults,
            wearingPhotoFiles: files
        )
        let fetched = await relaunched.fetchWearingPhotos(garmentId: garment.id)
        XCTAssertEqual(fetched, [photo])
        await relaunched.sweepOrphanWearingPhotoFiles()
        XCTAssertTrue(files.exists(photo.displayFileId), "sweep keeps referenced files")
    }

    @MainActor
    func testSweepWithNoRowsNeverDeletesFiles() async throws {
        for store in try makeStores() {
            let files = store.wearingPhotoFiles
            let file = try files.write(try Self.jpeg(.gray))
            try FileManager.default.setAttributes(
                [.modificationDate: Date().addingTimeInterval(-86_400)],
                ofItemAtPath: files.fileURL(for: file).path
            )
            await store.sweepOrphanWearingPhotoFiles()
            XCTAssertTrue(files.exists(file), "\(store.backendName): lost rows must not become lost photos")
        }
    }

    @MainActor
    func testRetryWithSameIdForAnotherGarmentIsRejected() async throws {
        for store in try makeStores() {
            let garment = try await seedGarment(in: store)
            let other = try await seedGarment(in: store, name: "Synthetic Cord Trousers")
            var req = request(garment.id)
            _ = try await store.addWearingPhoto(req)
            req.garmentId = other.id
            do {
                _ = try await store.addWearingPhoto(req)
                XCTFail("expected saveFailed")
            } catch {
                XCTAssertEqual(error as? WearingPhotoPersistError, .saveFailed)
            }
            let otherPhotos = await store.fetchWearingPhotos(garmentId: other.id)
            XCTAssertTrue(otherPhotos.isEmpty, store.backendName)
        }
    }

    @MainActor
    func testSweepRemovesOnlyOldUnreferencedFiles() async throws {
        for store in try makeStores() {
            let garment = try await seedGarment(in: store)
            let photo = try await store.addWearingPhoto(request(garment.id))
            let files = store.wearingPhotoFiles
            let staleOrphan = try files.write(try Self.jpeg(.gray))
            let freshOrphan = try files.write(try Self.jpeg(.gray))
            let old = Date().addingTimeInterval(-3600)
            try FileManager.default.setAttributes(
                [.modificationDate: old],
                ofItemAtPath: files.fileURL(for: staleOrphan).path
            )
            try FileManager.default.setAttributes(
                [.modificationDate: old],
                ofItemAtPath: files.fileURL(for: photo.displayFileId).path
            )

            await store.sweepOrphanWearingPhotoFiles()

            XCTAssertFalse(files.exists(staleOrphan), store.backendName)
            XCTAssertTrue(files.exists(freshOrphan), "a possibly in-flight file is kept")
            XCTAssertTrue(files.exists(photo.displayFileId))
            XCTAssertTrue(files.exists(try XCTUnwrap(photo.sourceFileId)))
        }
    }

    // MARK: - Provider boundary

    /// Engine requests are built from `StubGarment`; gallery data lives in a separate type
    /// and store, so no gallery field can reach a request DTO.
    @MainActor
    func testGarmentDTOCarriesNoGalleryFields() async throws {
        let store = try makeStores()[0]
        let garment = try await seedGarment(in: store)
        _ = try await store.addWearingPhoto(request(garment.id))
        let garments = await store.fetchGarments()
        let fetched = try XCTUnwrap(garments.first { $0.id == garment.id })
        let json = String(decoding: try JSONEncoder().encode(fetched), as: UTF8.self).lowercased()
        for token in ["wearing", "displayfileid", "sourcefileid", "addedat", "photosexport"] {
            XCTAssertFalse(json.contains(token), token)
        }
    }

    // MARK: - Helpers

    @MainActor
    private func makeStores() throws -> [PersistenceStore] {
        let container = try TestModelContainers.makeInMemory()
        let swiftData = SwiftDataPersistenceStore(
            container: container,
            defaults: defaults,
            wearingPhotoFiles: trackedFileStore()
        )
        let memory = InMemoryPersistenceStore(
            garments: [],
            defaults: defaults,
            wearingPhotoFiles: trackedFileStore()
        )
        return [swiftData, memory]
    }

    private func trackedFileStore(files: FileOperating = SystemFileOperations()) -> WearingPhotoFileStore {
        let store = WearingPhotoFileStore.temporary(files: files)
        fileStores.append(store)
        return store
    }

    private func jpegCount(_ files: WearingPhotoFileStore) -> Int {
        let urls = (try? FileManager.default.contentsOfDirectory(at: files.directory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "jpg" }.count
    }

    private func request(_ garmentId: UUID, at date: Date = Date()) -> WearingPhotoAddRequest {
        WearingPhotoAddRequest(
            garmentId: garmentId,
            displayJPEG: (try? Self.jpeg(.red)) ?? Data(),
            sourceJPEG: (try? Self.jpeg(.blue)) ?? Data(),
            source: .library,
            addedAt: date
        )
    }

    private func seedGarment(in store: PersistenceStore, name: String = "Synthetic Canvas Shirt") async throws -> StubGarment {
        let garment = StubGarment(
            id: UUID(),
            displayName: name,
            slot: .top,
            readiness: .ready,
            availability: "AVAILABLE",
            colorPrimary: StubColorPrimary(family: "navy", hex: "#1B2A4A", name: "Navy"),
            pattern: "SOLID",
            surface: "SMOOTH",
            imagePath: nil,
            formality: 2,
            warmth: 2,
            setId: nil,
            keepTogether: nil,
            lastWornOn: nil,
            daysSinceIntake: 0,
            createdAt: Date(timeIntervalSince1970: 1_699_000_000),
            displayNameSource: "USER",
            purchasePrice: 40,
            purchaseCurrency: "USD",
            attributeSource: ["slot": "USER"]
        )
        try await store.saveGarment(garment)
        return garment
    }

    static func jpeg(_ color: UIColor) throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
        let image = renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            throw NSError(domain: "WearingPhotoPersistTests", code: 1)
        }
        return data
    }
}

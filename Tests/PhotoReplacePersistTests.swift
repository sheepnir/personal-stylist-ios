import XCTest
import SwiftData
import UIKit
@testable import PersonalStylist

/// D-74 existing-garment photo replace — disposable JPEG + in-memory / temp SwiftData only.
final class PhotoReplacePersistTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaultsSuiteName = "PhotoReplacePersistTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        PhotoReplacePersistHooks.reset()
    }

    override func tearDownWithError() throws {
        PhotoReplacePersistHooks.reset()
        if let defaultsSuiteName {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }
        defaults = nil
        defaultsSuiteName = nil
        try super.tearDownWithError()
    }

    // MARK: - Success + relaunch

    @MainActor
    func testReplaceSurvivesRelaunchAndPreservesIdentity() async throws {
        let (directory, storeURL, first) = try TestModelContainers.makeOnDiskTemp()
        var alive: ModelContainer? = first
        defer {
            alive = nil
            try? FileManager.default.removeItem(at: directory)
        }

        let store = SwiftDataPersistenceStore(container: first, defaults: defaults)
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let garment = disposableGarment(
            name: "Replace Canvas Shirt",
            slot: .top,
            createdAt: createdAt,
            price: 42,
            setId: nil
        )
        let originalJPEG = try Self.makeTinyJPEG(color: .red)
        let originalPath = try UserGarmentPhotoStore.persistJPEG(from: originalJPEG, garmentId: garment.id)
        var seeded = garment
        seeded.imagePath = originalPath
        try await store.saveGarment(seeded)
        try await store.saveWearEvent(
            StubWearEvent(id: UUID(), garmentIds: [seeded.id], wornOn: Date(timeIntervalSince1970: 1_700_100_000))
        )
        try await store.saveOutfit(
            StubOutfit(
                id: UUID(),
                assignments: [
                    StubOutfitAssignment(slot: .top, garmentId: seeded.id, gapReason: nil, isAnchor: true)
                ],
                rationaleSummary: "test look",
                offlineCached: false
            )
        )

        let replacement = try Self.makeTinyJPEG(color: .blue)
        let updated = try await store.replaceGarmentPhoto(garmentId: seeded.id, jpegData: replacement)
        XCTAssertEqual(updated.id, seeded.id)
        XCTAssertEqual(updated.displayName, seeded.displayName)
        XCTAssertEqual(updated.slot, seeded.slot)
        XCTAssertEqual(updated.colorPrimary, seeded.colorPrimary)
        XCTAssertEqual(updated.pattern, seeded.pattern)
        XCTAssertEqual(updated.surface, seeded.surface)
        XCTAssertEqual(updated.formality, seeded.formality)
        XCTAssertEqual(updated.warmth, seeded.warmth)
        XCTAssertEqual(updated.purchasePrice, Decimal(42))
        XCTAssertEqual(updated.createdAt, createdAt)
        XCTAssertNotEqual(updated.imagePath, originalPath)
        XCTAssertNotEqual(updated.imagePath, UserGarmentPhotoStore.userPhotoPath(for: seeded.id))
        XCTAssertNotNil(UserGarmentPhotoStore.resolvedFileURL(updated.imagePath))
        XCTAssertNil(UserGarmentPhotoStore.resolvedFileURL(originalPath))

        let wears = await store.fetchWearEvents()
        XCTAssertEqual(wears.first?.garmentIds, [seeded.id])
        let outfits = await store.fetchOutfits()
        XCTAssertEqual(outfits.first?.assignments.first?.garmentId, seeded.id)
        let afterReplace = await store.fetchGarments()
        XCTAssertEqual(afterReplace.count, 1)

        alive = try TestModelContainers.restart(storeURL: storeURL, releasing: first)
        let relaunched = try XCTUnwrap(alive)
        let relaunchStore = SwiftDataPersistenceStore(container: relaunched, defaults: defaults)
        let relaunchedGarments = await relaunchStore.fetchGarments()
        let relaunchedGarment = try XCTUnwrap(relaunchedGarments.first)
        XCTAssertEqual(relaunchedGarment.id, seeded.id)
        XCTAssertEqual(relaunchedGarment.displayName, seeded.displayName)
        XCTAssertEqual(relaunchedGarment.slot, .top)
        XCTAssertEqual(relaunchedGarment.purchasePrice, Decimal(42))
        XCTAssertEqual(relaunchedGarment.createdAt, createdAt)
        XCTAssertEqual(relaunchedGarment.imagePath, updated.imagePath)
        XCTAssertNotNil(UserGarmentPhotoStore.resolvedFileURL(relaunchedGarment.imagePath))
        let relaunchWears = await relaunchStore.fetchWearEvents()
        XCTAssertEqual(relaunchWears.first?.garmentIds, [seeded.id])
        let relaunchOutfits = await relaunchStore.fetchOutfits()
        XCTAssertEqual(relaunchOutfits.count, 1)
        UserGarmentPhotoStore.removeFile(imagePath: updated.imagePath)
        alive = nil
    }

    func testRepeatSaveIsIdempotent() async throws {
        let store = InMemoryPersistenceStore(garments: [], sets: [], defaults: defaults)
        var garment = disposableGarment(name: "Repeat Shirt", slot: .bottom)
        let original = try UserGarmentPhotoStore.persistJPEG(from: try Self.makeTinyJPEG(color: .red), garmentId: garment.id)
        garment.imagePath = original
        try await store.saveGarment(garment)

        let jpeg = try Self.makeTinyJPEG(color: .green)
        let stagingId = try await store.stagePhotoReplace(garmentId: garment.id, jpegData: jpeg)
        let first = try await store.replaceGarmentPhoto(garmentId: garment.id, stagingId: stagingId)
        let second = try await store.replaceGarmentPhoto(garmentId: garment.id, stagingId: stagingId)
        XCTAssertEqual(first.imagePath, second.imagePath)
        let repeated = await store.fetchGarments()
        XCTAssertEqual(repeated.count, 1)
        XCTAssertEqual(repeated.first?.imagePath, first.imagePath)
        XCTAssertNotNil(UserGarmentPhotoStore.resolvedFileURL(first.imagePath))
        UserGarmentPhotoStore.removeFile(imagePath: first.imagePath)
    }

    func testConcurrentCommitsSerializeToOneOwnedFile() async throws {
        let store = InMemoryPersistenceStore(garments: [], sets: [], defaults: defaults)
        var garment = disposableGarment(name: "Overlap Shirt", slot: .top)
        let original = try UserGarmentPhotoStore.persistJPEG(
            from: try Self.makeTinyJPEG(color: .red),
            garmentId: garment.id
        )
        garment.imagePath = original
        try await store.saveGarment(garment)

        let firstId = try await store.stagePhotoReplace(
            garmentId: garment.id,
            jpegData: try Self.makeTinyJPEG(color: .blue)
        )
        let secondId = try await store.stagePhotoReplace(
            garmentId: garment.id,
            jpegData: try Self.makeTinyJPEG(color: .green)
        )
        PhotoReplacePersistHooks.delayNanoseconds = 80_000_000

        async let firstCommit = store.replaceGarmentPhoto(garmentId: garment.id, stagingId: firstId)
        async let secondCommit = store.replaceGarmentPhoto(garmentId: garment.id, stagingId: secondId)
        let first = try await firstCommit
        let second = try await secondCommit

        XCTAssertEqual(first.id, garment.id)
        XCTAssertEqual(second.id, garment.id)
        let stored = await store.fetchGarments()
        XCTAssertEqual(stored.count, 1)
        let path = try XCTUnwrap(stored.first?.imagePath)
        XCTAssertEqual(stored.first?.id, garment.id)
        XCTAssertNotEqual(path, original)
        XCTAssertNil(UserGarmentPhotoStore.resolvedFileURL(original))
        XCTAssertNotNil(UserGarmentPhotoStore.resolvedFileURL(path))

        let firstPath = UserGarmentPhotoStore.userPhotoPath(for: firstId)
        let secondPath = UserGarmentPhotoStore.userPhotoPath(for: secondId)
        let firstExists = UserGarmentPhotoStore.resolvedFileURL(firstPath) != nil
        let secondExists = UserGarmentPhotoStore.resolvedFileURL(secondPath) != nil
        XCTAssertEqual((firstExists ? 1 : 0) + (secondExists ? 1 : 0), 1, "exactly one owned replacement file")
        XCTAssertTrue(path == firstPath || path == secondPath)
        UserGarmentPhotoStore.removeFile(imagePath: path)
    }

    // MARK: - Cancel / fail leave original

    func testStageCancelLeavesOriginal() async throws {
        let store = InMemoryPersistenceStore(garments: [], sets: [], defaults: defaults)
        var garment = disposableGarment(name: "Cancel Shirt", slot: .jacket)
        let original = try UserGarmentPhotoStore.persistJPEG(from: try Self.makeTinyJPEG(color: .red), garmentId: garment.id)
        garment.imagePath = original
        try await store.saveGarment(garment)

        let stagingId = try await store.stagePhotoReplace(
            garmentId: garment.id,
            jpegData: try Self.makeTinyJPEG(color: .blue)
        )
        XCTAssertNotNil(UserGarmentPhotoStore.resolvedFileURL(UserGarmentPhotoStore.replacePhotoPath(for: stagingId)))
        try await store.abandonPhotoReplace(stagingId: stagingId)
        try await store.abandonPhotoReplace(stagingId: stagingId)

        let cancelled = await store.fetchGarments()
        let stored = try XCTUnwrap(cancelled.first)
        XCTAssertEqual(stored.id, garment.id)
        XCTAssertEqual(stored.imagePath, original)
        XCTAssertNotNil(UserGarmentPhotoStore.resolvedFileURL(original))
        XCTAssertNil(UserGarmentPhotoStore.resolvedFileURL(UserGarmentPhotoStore.replacePhotoPath(for: stagingId)))
        UserGarmentPhotoStore.removeFile(imagePath: original)
    }

    func testDecodeFailureLeavesOriginalAndNoStaging() async throws {
        let store = InMemoryPersistenceStore(garments: [], sets: [], defaults: defaults)
        var garment = disposableGarment(name: "Decode Shirt", slot: .top)
        let original = try UserGarmentPhotoStore.persistJPEG(from: try Self.makeTinyJPEG(color: .red), garmentId: garment.id)
        garment.imagePath = original
        try await store.saveGarment(garment)

        do {
            _ = try await store.stagePhotoReplace(garmentId: garment.id, jpegData: Data([0x00, 0x01, 0x02]))
            XCTFail("undecodable data must fail")
        } catch PhotoReplacePersistError.undecodableImage {
            // expected
        }

        let afterDecode = await store.fetchGarments()
        let stored = try XCTUnwrap(afterDecode.first)
        XCTAssertEqual(stored.imagePath, original)
        XCTAssertNotNil(UserGarmentPhotoStore.resolvedFileURL(original))
        UserGarmentPhotoStore.removeFile(imagePath: original)
    }

    func testCommitFailKeepsOriginalAndCleansStaging() async throws {
        let store = InMemoryPersistenceStore(garments: [], sets: [], defaults: defaults)
        var garment = disposableGarment(name: "Fail Shirt", slot: .top)
        let original = try UserGarmentPhotoStore.persistJPEG(from: try Self.makeTinyJPEG(color: .red), garmentId: garment.id)
        garment.imagePath = original
        try await store.saveGarment(garment)

        let stagingId = try await store.stagePhotoReplace(
            garmentId: garment.id,
            jpegData: try Self.makeTinyJPEG(color: .blue)
        )
        PhotoReplacePersistHooks.failBeforeMetadataCommit = PhotoReplacePersistError.saveFailed
        do {
            _ = try await store.replaceGarmentPhoto(garmentId: garment.id, stagingId: stagingId)
            XCTFail("injected commit failure must throw")
        } catch PhotoReplacePersistError.saveFailed {
            // expected
        }

        let afterFail = await store.fetchGarments()
        let stored = try XCTUnwrap(afterFail.first)
        XCTAssertEqual(stored.imagePath, original)
        XCTAssertNotNil(UserGarmentPhotoStore.resolvedFileURL(original))
        XCTAssertNil(UserGarmentPhotoStore.resolvedFileURL(UserGarmentPhotoStore.replacePhotoPath(for: stagingId)))
        UserGarmentPhotoStore.removeFile(imagePath: original)
    }

    func testStageFailureAfterFileWriteCleansStaging() async throws {
        let store = InMemoryPersistenceStore(garments: [], sets: [], defaults: defaults)
        var garment = disposableGarment(name: "Stage Fail Shirt", slot: .top)
        let original = try UserGarmentPhotoStore.persistJPEG(from: try Self.makeTinyJPEG(color: .red), garmentId: garment.id)
        garment.imagePath = original
        try await store.saveGarment(garment)

        PhotoReplacePersistHooks.failAfterStagingFileWrite = PhotoReplacePersistError.lowStorage
        do {
            _ = try await store.stagePhotoReplace(
                garmentId: garment.id,
                jpegData: try Self.makeTinyJPEG(color: .blue)
            )
            XCTFail("injected stage failure must throw")
        } catch PhotoReplacePersistError.lowStorage {
            // expected
        }
        let afterStageFail = await store.fetchGarments()
        let stored = try XCTUnwrap(afterStageFail.first)
        XCTAssertEqual(stored.imagePath, original)
        XCTAssertNotNil(UserGarmentPhotoStore.resolvedFileURL(original))
        if let staged = PhotoReplacePersistHooks.lastStagedPath {
            XCTAssertNil(UserGarmentPhotoStore.resolvedFileURL(staged))
        }
        UserGarmentPhotoStore.removeFile(imagePath: original)
    }

    // MARK: - Shared / fixture never deleted

    func testFixturePathIsNeverDeleted() async throws {
        let store = InMemoryPersistenceStore(garments: [], sets: [], defaults: defaults)
        let fixturePath = "images/synthetic_fixture.svg"
        XCTAssertFalse(UserGarmentPhotoStore.isOwnedUserFile(fixturePath))
        var garment = disposableGarment(name: "Fixture Shirt", slot: .top)
        garment.imagePath = fixturePath
        try await store.saveGarment(garment)

        let updated = try await store.replaceGarmentPhoto(
            garmentId: garment.id,
            jpegData: try Self.makeTinyJPEG(color: .blue)
        )
        XCTAssertNotEqual(updated.imagePath, fixturePath)
        XCTAssertFalse(UserGarmentPhotoStore.isOwnedUserFile(fixturePath))
        UserGarmentPhotoStore.removeFile(imagePath: updated.imagePath)
    }

    func testSharedOwnedFileIsNotDeleted() async throws {
        let store = InMemoryPersistenceStore(garments: [], sets: [], defaults: defaults)
        var owner = disposableGarment(name: "Owner Shirt", slot: .top)
        var peer = disposableGarment(name: "Peer Shirt", slot: .bottom)
        let shared = try UserGarmentPhotoStore.persistJPEG(from: try Self.makeTinyJPEG(color: .red), garmentId: owner.id)
        owner.imagePath = shared
        peer.imagePath = shared
        try await store.saveGarment(owner)
        try await store.saveGarment(peer)

        let updated = try await store.replaceGarmentPhoto(
            garmentId: owner.id,
            jpegData: try Self.makeTinyJPEG(color: .blue)
        )
        XCTAssertNotEqual(updated.imagePath, shared)
        XCTAssertNotNil(UserGarmentPhotoStore.resolvedFileURL(shared), "shared original must remain for the peer")
        let peers = await store.fetchGarments()
        let peerStored = try XCTUnwrap(peers.first { $0.id == peer.id })
        XCTAssertEqual(peerStored.imagePath, shared)
        UserGarmentPhotoStore.removeFile(imagePath: updated.imagePath)
        UserGarmentPhotoStore.removeFile(imagePath: shared)
    }

    // MARK: - Delete / clear race

    func testLateReplaceAfterDeleteDoesNotResurrect() async throws {
        let store = InMemoryPersistenceStore(garments: [], sets: [], defaults: defaults)
        var garment = disposableGarment(name: "Delete Race Shirt", slot: .top)
        let original = try UserGarmentPhotoStore.persistJPEG(from: try Self.makeTinyJPEG(color: .red), garmentId: garment.id)
        garment.imagePath = original
        try await store.saveGarment(garment)

        let stagingId = try await store.stagePhotoReplace(
            garmentId: garment.id,
            jpegData: try Self.makeTinyJPEG(color: .blue)
        )
        try await store.deleteGarment(id: garment.id)
        do {
            _ = try await store.replaceGarmentPhoto(garmentId: garment.id, stagingId: stagingId)
            XCTFail("replace after delete must fail")
        } catch PhotoReplacePersistError.garmentUnavailable {
            // expected
        }
        let afterDelete = await store.fetchGarments()
        XCTAssertTrue(afterDelete.isEmpty)
        XCTAssertNil(UserGarmentPhotoStore.resolvedFileURL(UserGarmentPhotoStore.replacePhotoPath(for: stagingId)))
    }

    func testLateReplaceAfterClearDoesNotResurrect() async throws {
        let store = InMemoryPersistenceStore(garments: [], sets: [], defaults: defaults)
        var garment = disposableGarment(name: "Clear Race Shirt", slot: .top)
        let original = try UserGarmentPhotoStore.persistJPEG(from: try Self.makeTinyJPEG(color: .red), garmentId: garment.id)
        garment.imagePath = original
        try await store.saveGarment(garment)

        let stagingId = try await store.stagePhotoReplace(
            garmentId: garment.id,
            jpegData: try Self.makeTinyJPEG(color: .blue)
        )
        try await store.clearWardrobeAndLooks()
        do {
            _ = try await store.replaceGarmentPhoto(garmentId: garment.id, stagingId: stagingId)
            XCTFail("replace after clear must fail")
        } catch PhotoReplacePersistError.garmentUnavailable {
            // expected
        }
        let afterClear = await store.fetchGarments()
        XCTAssertTrue(afterClear.isEmpty)
        XCTAssertNil(UserGarmentPhotoStore.resolvedFileURL(UserGarmentPhotoStore.replacePhotoPath(for: stagingId)))
    }

    func testStageAfterDeleteFails() async throws {
        let store = InMemoryPersistenceStore(garments: [], sets: [], defaults: defaults)
        let garment = disposableGarment(name: "Gone Shirt", slot: .top)
        try await store.saveGarment(garment)
        try await store.deleteGarment(id: garment.id)
        do {
            _ = try await store.stagePhotoReplace(
                garmentId: garment.id,
                jpegData: try Self.makeTinyJPEG(color: .blue)
            )
            XCTFail("stage after delete must fail")
        } catch PhotoReplacePersistError.garmentUnavailable {
            // expected
        }
        let afterGone = await store.fetchGarments()
        XCTAssertTrue(afterGone.isEmpty)
    }

    @MainActor
    func testModelCommitRefreshesGarmentAndRepeatSave() async throws {
        let store = InMemoryPersistenceStore(garments: [], sets: [], defaults: defaults)
        var garment = disposableGarment(name: "Model Shirt", slot: .top)
        let original = try UserGarmentPhotoStore.persistJPEG(from: try Self.makeTinyJPEG(color: .red), garmentId: garment.id)
        garment.imagePath = original
        try await store.saveGarment(garment)
        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()
        model.bindPhotoReplaceStore(store)

        let pending = try await model.beginPhotoReplace(
            garmentId: garment.id,
            jpegData: try Self.makeTinyJPEG(color: .blue)
        )
        let stagedOnly = await store.fetchGarments()
        XCTAssertEqual(stagedOnly.first?.imagePath, original)
        let firstCommit = await model.commitPhotoReplace(garmentId: garment.id, stagingId: pending.id)
        XCTAssertTrue(firstCommit)
        XCTAssertEqual(model.garments.first?.id, garment.id)
        XCTAssertNotEqual(model.garments.first?.imagePath, original)
        let secondCommit = await model.commitPhotoReplace(garmentId: garment.id, stagingId: pending.id)
        XCTAssertTrue(secondCommit)
        XCTAssertEqual(model.garments.count, 1)
        UserGarmentPhotoStore.removeFile(imagePath: model.garments.first?.imagePath)
    }

    // MARK: - Helpers

    private func disposableGarment(
        name: String,
        slot: StubSlot,
        createdAt: Date = Date(timeIntervalSince1970: 1_699_000_000),
        price: Decimal? = 18,
        setId: UUID? = nil
    ) -> StubGarment {
        StubGarment(
            id: UUID(),
            displayName: name,
            slot: slot,
            readiness: .ready,
            availability: "AVAILABLE",
            colorPrimary: StubColorPrimary(family: "navy", hex: "#1B2A4A", name: "Navy"),
            pattern: "SOLID",
            surface: "SMOOTH",
            imagePath: nil,
            formality: 2,
            warmth: 2,
            setId: setId,
            keepTogether: nil,
            lastWornOn: nil,
            daysSinceIntake: 0,
            createdAt: createdAt,
            displayNameSource: "USER",
            purchasePrice: price,
            purchaseCurrency: "USD",
            attributeSource: ["slot": "USER", "color": "USER"]
        )
    }

    private static func makeTinyJPEG(color: UIColor) throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let image = renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            throw NSError(domain: "PhotoReplacePersistTests", code: 1)
        }
        return data
    }
}

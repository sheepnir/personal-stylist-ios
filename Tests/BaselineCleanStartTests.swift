import SwiftData
import XCTest
@testable import PersonalStylist

@MainActor
final class BaselineCleanStartTests: XCTestCase {
    private var defaultsName = ""
    private var defaults: UserDefaults!
    private var root: URL!

    override func setUpWithError() throws {
        defaultsName = "baseline-clean-start-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defaults.removePersistentDomain(forName: defaultsName)
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: defaultsName)
        try? FileManager.default.removeItem(at: root)
    }

    func testPreexistingStoreAndPhotosAreRemovedOnce() throws {
        let support = root.appendingPathComponent("Application Support", isDirectory: true)
        let documents = root.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)

        let storeURL = support.appendingPathComponent("PersonalStylistLocal.store")
        try autoreleasepool {
            let prior = try AppModelContainer.make(at: storeURL)
            let priorContext = ModelContext(prior)
            priorContext.insert(GarmentEntity(displayName: "old coat", slotRaw: "outerwear", readinessRaw: "READY"))
            try priorContext.save()
        }

        let photos = documents.appendingPathComponent(UserGarmentPhotoStore.directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
        let oldPhoto = photos.appendingPathComponent("old.jpg")
        try Data("old-photo".utf8).write(to: oldPhoto)

        try BaselineCleanStart.runIfNeeded(
            defaults: defaults,
            applicationSupport: support,
            documents: documents
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldPhoto.path))
        XCTAssertTrue(defaults.bool(forKey: BaselineCleanStart.completedKey))
        XCTAssertTrue(SeedSuppression.isAutomaticWardrobeSeedSuppressed(in: defaults))
        XCTAssertTrue(SeedSuppression.isAutomaticProfileSeedSuppressed(in: defaults))
    }

    func testDataAddedAfterCleanStartSurvivesRelaunchAndALaterUpdate() throws {
        let support = root.appendingPathComponent("Application Support", isDirectory: true)
        let documents = root.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        let storeURL = support.appendingPathComponent("PersonalStylistLocal.store")
        try Data("pre-baseline".utf8).write(to: storeURL)

        try BaselineCleanStart.runIfNeeded(
            defaults: defaults,
            applicationSupport: support,
            documents: documents
        )

        let garmentId = UUID()
        let profileId = UUID()
        let wearId = UUID()
        let photoBytes = Data("kept-photo".utf8)
        var baseline: ModelContainer? = try AppModelContainer.make(at: storeURL)
        let context = ModelContext(baseline!)
        let profile = StyleProfileEntity(id: profileId, profession: "architect")
        let garment = GarmentEntity(
            id: garmentId,
            displayName: "navy coat",
            slotRaw: "outerwear",
            readinessRaw: "READY",
            imagePath: UserGarmentPhotoStore.userPhotoPath(for: garmentId)
        )
        let wear = WearEventEntity(id: wearId, garmentIds: [garmentId])
        context.insert(profile)
        context.insert(garment)
        context.insert(wear)
        try context.save()
        baseline = nil

        let photos = documents.appendingPathComponent(UserGarmentPhotoStore.directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
        let photoURL = photos.appendingPathComponent("\(garmentId.uuidString).jpg")
        try photoBytes.write(to: photoURL)

        try BaselineCleanStart.runIfNeeded(
            defaults: defaults,
            applicationSupport: support,
            documents: documents
        )
        try BaselineCleanStart.runIfNeeded(
            defaults: defaults,
            applicationSupport: support,
            documents: documents
        )

        let reopened = try AppModelContainer.make(at: storeURL)
        let check = ModelContext(reopened)
        let profiles = try check.fetch(FetchDescriptor<StyleProfileEntity>())
        let garments = try check.fetch(FetchDescriptor<GarmentEntity>())
        let wears = try check.fetch(FetchDescriptor<WearEventEntity>())
        XCTAssertEqual(profiles.map(\.id), [profileId])
        XCTAssertEqual(profiles.first?.profession, "architect")
        XCTAssertEqual(garments.map(\.id), [garmentId])
        XCTAssertEqual(garments.first?.displayName, "navy coat")
        XCTAssertEqual(wears.map(\.id), [wearId])
        XCTAssertEqual(wears.first?.garmentIds, [garmentId])
        XCTAssertEqual(try Data(contentsOf: photoURL), photoBytes)
    }

    func testFailedStoreDeleteLeavesDataAndDoesNotSetTheFrozenKey() throws {
        let layout = try makeLayout()
        try Data("store".utf8).write(to: layout.storeURL)
        try FileManager.default.createDirectory(at: layout.photos, withIntermediateDirectories: true)
        try Data("photo".utf8).write(to: layout.photos.appendingPathComponent("keep.jpg"))
        let files = FailRemove(onSuffix: "PersonalStylistLocal.store")

        XCTAssertThrowsError(try BaselineCleanStart.runIfNeeded(
            defaults: defaults,
            fileSystem: files,
            applicationSupport: layout.support,
            documents: layout.documents
        ))
        XCTAssertFalse(defaults.bool(forKey: BaselineCleanStart.completedKey))
        XCTAssertFalse(SeedSuppression.isAutomaticWardrobeSeedSuppressed(in: defaults))
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.storeURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.photos.appendingPathComponent("keep.jpg").path))
    }

    func testFailedPhotoDeleteRetriesOnceWithoutASecondKey() throws {
        let layout = try makeLayout()
        try Data("store".utf8).write(to: layout.storeURL)
        try FileManager.default.createDirectory(at: layout.photos, withIntermediateDirectories: true)
        try Data("photo".utf8).write(to: layout.photos.appendingPathComponent("old.jpg"))
        let files = FailRemove(onSuffix: UserGarmentPhotoStore.directoryName)

        XCTAssertThrowsError(try BaselineCleanStart.runIfNeeded(
            defaults: defaults,
            fileSystem: files,
            applicationSupport: layout.support,
            documents: layout.documents
        ))
        XCTAssertFalse(defaults.bool(forKey: BaselineCleanStart.completedKey))
        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.storeURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.photos.path))

        try BaselineCleanStart.runIfNeeded(
            defaults: defaults,
            applicationSupport: layout.support,
            documents: layout.documents
        )
        XCTAssertTrue(defaults.bool(forKey: BaselineCleanStart.completedKey))
        XCTAssertEqual(BaselineCleanStart.completedKey, "baseline.2026092602.cleanStartCompleted")
        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.photos.path))

        let kept = layout.support.appendingPathComponent("PersonalStylistLocal.store")
        try Data("after".utf8).write(to: kept)
        try BaselineCleanStart.runIfNeeded(
            defaults: defaults,
            applicationSupport: layout.support,
            documents: layout.documents
        )
        XCTAssertEqual(try Data(contentsOf: kept), Data("after".utf8))
    }

    private func makeLayout() throws -> (support: URL, documents: URL, photos: URL, storeURL: URL) {
        let support = root.appendingPathComponent("Application Support", isDirectory: true)
        let documents = root.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        let photos = documents.appendingPathComponent(UserGarmentPhotoStore.directoryName, isDirectory: true)
        let storeURL = support.appendingPathComponent("PersonalStylistLocal.store")
        return (support, documents, photos, storeURL)
    }
}

private final class FailRemove: BaselineFileSystem {
    let onSuffix: String
    init(onSuffix: String) { self.onSuffix = onSuffix }

    func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions
    ) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: mask)
    }

    func removeItem(at url: URL) throws {
        if url.lastPathComponent == onSuffix || url.lastPathComponent.hasSuffix(onSuffix) {
            throw CocoaError(.fileWriteUnknown)
        }
        try FileManager.default.removeItem(at: url)
    }
}

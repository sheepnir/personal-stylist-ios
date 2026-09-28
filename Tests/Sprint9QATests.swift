import XCTest
import SwiftUI
import UIKit
@testable import PersonalStylist

/// Sprint 9 QA gaps (#118): the real engine request body, calendar membership through the
/// model, read-only calendar hosting, and low-storage mapping. Synthetic data only.
@MainActor
final class Sprint9QATests: XCTestCase {
    private var defaultsSuite: String!
    private var defaults: UserDefaults!
    private var files: WearingPhotoFileStore!
    private var window: UIWindow?

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaultsSuite = "Sprint9QATests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuite)
        files = .temporary()
    }

    override func tearDownWithError() throws {
        window?.isHidden = true
        window = nil
        try? FileManager.default.removeItem(at: files.directory)
        defaults.removePersistentDomain(forName: defaultsSuite)
        try super.tearDownWithError()
    }

    /// The body actually posted to the engine carries no gallery ids, photo paths or pixels.
    func testEngineRequestBodyCarriesNoGalleryOrPhotoData() async throws {
        var garment = garment(name: "Synthetic Boundary Shirt")
        garment.imagePath = UserGarmentPhotoStore.userPhotoPath(for: garment.id)
        let store = InMemoryPersistenceStore(garments: [garment], sets: [], defaults: defaults, wearingPhotoFiles: files)
        let photo = try await store.addWearingPhoto(
            WearingPhotoAddRequest(
                garmentId: garment.id,
                displayJPEG: try Self.jpeg(),
                sourceJPEG: try Self.jpeg(),
                source: .camera
            )
        )
        let garments = await store.fetchGarments()
        let body: [String: Any] = [
            "wardrobe": OutfitEngineClient.wardrobeRows(from: garments),
            "anchor": OutfitEngineClient.garmentSummary(from: garments[0]),
        ]
        let json = String(decoding: try OutfitEngineClient.encodeRequestBody(body), as: UTF8.self).lowercased()
        XCTAssertTrue(json.contains(garment.id.uuidString.lowercased()), "sanity: the garment itself is sent")
        for forbidden in [
            "user-photo", "wearing", "/9j/", "imagepath",
            photo.displayFileId.uuidString.lowercased(),
            try XCTUnwrap(photo.sourceFileId).uuidString.lowercased(),
        ] {
            XCTAssertFalse(json.contains(forbidden), forbidden)
        }
    }

    /// History comes from the stored wear event, never from the mutable current outfit.
    func testCalendarKeepsStoredMembershipAfterBoardChanges() async throws {
        let worn = [garment(name: "Synthetic Worn Top"), garment(name: "Synthetic Worn Trousers", slot: .bottom)]
        let other = garment(name: "Synthetic Swapped Top")
        let store = InMemoryPersistenceStore(garments: worn + [other], sets: [], defaults: defaults, wearingPhotoFiles: files)
        let wornOn = Date()
        let outfitId = UUID()
        try await store.saveWearEvent(
            StubWearEvent(id: UUID(), garmentIds: worn.map(\.id), wornOn: wornOn, sourceOutfitId: outfitId)
        )
        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()
        model.outfit = StubOutfit(
            id: outfitId,
            assignments: [StubOutfitAssignment(slot: .top, garmentId: other.id, gapReason: nil, isAnchor: true)],
            rationaleSummary: "",
            offlineCached: false
        )
        let day = WearCalendar.day(for: wornOn, calendar: .current)
        let records = WearCalendar.records(on: day, events: model.wearEvents, calendar: .current)
        XCTAssertEqual(records.first?.garmentIds, worn.map(\.id))
        let resolved = WearCalendar.resolve(try XCTUnwrap(records.first), garments: model.garments, id: \.id)
        XCTAssertEqual(resolved.available.map(\.id), worn.map(\.id))
        XCTAssertFalse(resolved.available.contains { $0.id == other.id })
    }

    /// Hosting and browsing the calendar writes nothing and never generates.
    func testHostedCalendarIsReadOnly() async throws {
        let worn = garment(name: "Synthetic Calendar Coat", slot: .outerwear)
        let store = InMemoryPersistenceStore(garments: [worn], sets: [], defaults: defaults, wearingPhotoFiles: files)
        try await store.saveWearEvent(StubWearEvent(id: UUID(), garmentIds: [worn.id], wornOn: Date()))
        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()
        let before = await store.fetchWearAggregates()
        let eventsBefore = await store.fetchWearEvents()
        let garmentsBefore = await store.fetchGarments()

        let host = UIHostingController(rootView: NavigationStack { WearCalendarView(model: model) })
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        window.windowScene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        self.window = window
        try await Task.sleep(for: .milliseconds(500))

        let after = await store.fetchWearAggregates()
        let eventsAfter = await store.fetchWearEvents()
        let garmentsAfter = await store.fetchGarments()
        XCTAssertEqual(after, before)
        XCTAssertEqual(eventsAfter, eventsBefore)
        XCTAssertEqual(garmentsAfter, garmentsBefore, "prices and garments unchanged")
        XCTAssertNil(model.generateIntent)
        XCTAssertFalse(model.isGenerating)
    }

    func testLowStorageMapsToCalmCopy() {
        let posix = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
        let cocoa = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
        XCTAssertEqual(WearingPhotoPersistError.map(posix), .lowStorage)
        XCTAssertEqual(WearingPhotoPersistError.map(cocoa), .lowStorage)
        XCTAssertEqual(WearingPhotoPersistError.map(NSError(domain: "other", code: 1)), .saveFailed)
        let copy = WearingGalleryCopy.saveFailure(.lowStorage)
        XCTAssertTrue(copy.localizedCaseInsensitiveContains("storage"))
        XCTAssertFalse(copy.contains("NSError") || copy.contains("POSIX"), "no machine tokens in copy")
    }

    // MARK: - Helpers

    private func garment(name: String, slot: StubSlot = .top) -> StubGarment {
        StubGarment(
            id: UUID(), displayName: name, slot: slot, readiness: .ready, availability: "AVAILABLE",
            colorPrimary: nil, pattern: "SOLID", surface: "SMOOTH", imagePath: nil, formality: 2, warmth: 2,
            setId: nil, keepTogether: nil, lastWornOn: nil, daysSinceIntake: 0,
            purchasePrice: 30, purchaseCurrency: "USD"
        )
    }

    private static func jpeg() throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4), format: format).image { ctx in
            UIColor.purple.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        return try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
    }
}

import XCTest
import SwiftData
@testable import PersonalStylist

/// D-75 / #103 / #125 — new wear vs correction vs Logged today.
/// Disposable in-memory and on-disk stores only.
final class DailyWearModelTests: XCTestCase {
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaultsSuiteName = "DailyWearModelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)
    }

    override func tearDownWithError() throws {
        if let defaultsSuiteName {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }
        defaults = nil
        defaultsSuiteName = nil
        try super.tearDownWithError()
    }

    // MARK: - Preselection

    @MainActor
    func testPreselectsEligibleSuggestedPiecesAndSkipsUnavailableOrDeleted() async throws {
        let shirt = disposableGarment(name: "Navy Oxford Shirt", slot: .top)
        var laundry = disposableGarment(name: "Ink Trousers", slot: .bottom)
        laundry.availability = "LAUNDRY"
        let missingId = UUID()
        let store = InMemoryPersistenceStore(garments: [shirt, laundry], sets: [], defaults: defaults)
        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()
        model.outfit = StubOutfit(
            id: UUID(),
            assignments: [
                StubOutfitAssignment(slot: .top, garmentId: shirt.id, gapReason: nil, isAnchor: true),
                StubOutfitAssignment(slot: .bottom, garmentId: laundry.id, gapReason: nil, isAnchor: false),
                StubOutfitAssignment(slot: .footwear, garmentId: missingId, gapReason: nil, isAnchor: false),
            ],
            rationaleSummary: "test",
            offlineCached: false
        )

        let preselected = model.dailyWearPreselectedIds()
        XCTAssertEqual(preselected, [shirt.id])
        XCTAssertFalse(preselected.contains(laundry.id))
        XCTAssertFalse(preselected.contains(missingId))

        let sections = model.dailyWearPickerSections(search: "")
        XCTAssertEqual(sections.first?.title, StubSlot.top.displayLabel)
        XCTAssertEqual(sections.first?.garments.map(\.id), [shirt.id])
        let unavailable = try XCTUnwrap(sections.first(where: \.isUnavailableGroup))
        XCTAssertEqual(unavailable.title, DailyWearCopy.notAvailableToday)
        XCTAssertEqual(unavailable.garments.map(\.id), [laundry.id])

        let search = model.dailyWearPickerSections(search: "oxford")
        XCTAssertEqual(search.flatMap(\.garments).map(\.id), [shirt.id])
        XCTAssertTrue(model.dailyWearPickerSections(search: "zzz").isEmpty)
    }

    @MainActor
    func testDraftsAreNotEligibleAndEmptySelectionWritesNothing() async throws {
        var draft = disposableGarment(name: "Untitled Top", slot: .top)
        draft.readiness = .draft
        let ready = disposableGarment(name: "Navy Oxford Shirt", slot: .top)
        let store = InMemoryPersistenceStore(garments: [draft, ready], sets: [], defaults: defaults)
        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()

        XCTAssertFalse(model.isEligibleForDailyWear(draft))
        XCTAssertTrue(model.dailyWearPickerSections(search: "").flatMap(\.garments).allSatisfy(\.isReady))

        let completion = await model.submitDailyWear(garmentIds: [draft.id])
        XCTAssertEqual(completion, .remain)
        XCTAssertEqual(model.wearConfirmedMessage, DailyWearCopy.blockedDrafts)
        let events = await store.fetchWearEvents()
        XCTAssertTrue(events.isEmpty)
        XCTAssertFalse(model.hasLoggedToday)
        XCTAssertFalse(model.dailyWearShowsSuccessChrome)
    }

    // MARK: - New vs correction vs cancel

    @MainActor
    func testNewWearThenCorrectionThenCancelLeavesPriorCount() async throws {
        let shirt = disposableGarment(name: "Navy Oxford Shirt", slot: .top)
        let pants = disposableGarment(name: "Ink Trousers", slot: .bottom)
        let store = InMemoryPersistenceStore(garments: [shirt, pants], sets: [], defaults: defaults)
        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()
        XCTAssertEqual(model.dailyWearMode, .newWear)

        let first = await model.submitDailyWear(garmentIds: [shirt.id])
        XCTAssertEqual(first, .popToWardrobe)
        XCTAssertEqual(model.dailyWearMode, .correction)
        XCTAssertEqual(model.wearCount(for: shirt.id), 1)
        XCTAssertEqual(model.wearCount(for: pants.id), 0)
        XCTAssertTrue(model.showsLoggedTodayRow)
        XCTAssertFalse(model.showsReturnToOutfitBanner)
        XCTAssertTrue(model.dailyWearShowsSuccessChrome)

        let beforeCorrection = await store.fetchWearEvents()
        XCTAssertEqual(beforeCorrection.filter { !$0.isVoided }.count, 1)

        model.cancelDailyWearCorrection()
        let afterCancel = await store.fetchWearEvents()
        XCTAssertEqual(afterCancel.map(\.id), beforeCorrection.map(\.id))
        XCTAssertEqual(afterCancel.map(\.voidedAt), beforeCorrection.map(\.voidedAt))
        XCTAssertEqual(model.wearCount(for: shirt.id), 1)

        let corrected = await model.submitDailyWear(garmentIds: [shirt.id, pants.id])
        XCTAssertEqual(corrected, .popToWardrobe)
        XCTAssertEqual(model.wearCount(for: shirt.id), 1)
        XCTAssertEqual(model.wearCount(for: pants.id), 1)
        let active = WearLogging.activeSameDay(events: await store.fetchWearEvents(), day: Date())
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(Set(active[0].garmentIds), [shirt.id, pants.id])
        XCTAssertEqual(model.loggedTodaySnapshot()?.garments.map(\.id).sorted { $0.uuidString < $1.uuidString },
                       [shirt.id, pants.id].sorted { $0.uuidString < $1.uuidString })
    }

    @MainActor
    func testWearLoggingConfirmStillVoidsThenInserts() {
        let a = UUID()
        let b = UUID()
        let existing = StubWearEvent(id: UUID(), garmentIds: [a], wornOn: Date())
        let result = WearLogging.confirm(
            existing: [existing],
            garmentIds: [a, b],
            wornOn: Date(),
            sourceOutfitId: nil
        )
        XCTAssertEqual(result.voided.count, 1)
        XCTAssertEqual(result.voided.first?.id, existing.id)
        XCTAssertNotNil(result.voided.first?.voidedAt)
        XCTAssertNotNil(result.event)
        XCTAssertNotEqual(result.event?.id, existing.id)
        XCTAssertTrue(result.didWrite)
    }

    // MARK: - Idempotent repeat + failed persist

    @MainActor
    func testRepeatSubmitIsIdempotent() async throws {
        let shirt = disposableGarment(name: "Navy Oxford Shirt", slot: .top)
        let store = InMemoryPersistenceStore(garments: [shirt], sets: [], defaults: defaults)
        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()

        let first = await model.submitDailyWear(garmentIds: [shirt.id])
        let second = await model.submitDailyWear(garmentIds: [shirt.id])
        XCTAssertEqual(first, .popToWardrobe)
        XCTAssertEqual(second, .popToWardrobe)
        XCTAssertEqual(model.wearConfirmedMessage, DailyWearCopy.alreadyLogged)
        let events = await store.fetchWearEvents()
        XCTAssertEqual(events.filter { !$0.isVoided }.count, 1)
        XCTAssertEqual(model.wearCount(for: shirt.id), 1)
    }

    @MainActor
    func testFailedPersistShowsNoSuccessChromeAndWritesNothing() async throws {
        let shirt = disposableGarment(name: "Navy Oxford Shirt", slot: .top)
        let inner = InMemoryPersistenceStore(garments: [shirt], sets: [], defaults: defaults)
        let store = FailingWearStore(inner: inner)
        store.failOnSaveIndex = 0
        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()

        let completion = await model.submitDailyWear(garmentIds: [shirt.id])
        XCTAssertEqual(completion, .remain)
        XCTAssertEqual(model.wearConfirmedMessage, DailyWearCopy.persistFailed)
        XCTAssertFalse(model.hasLoggedToday)
        XCTAssertFalse(model.dailyWearShowsSuccessChrome)
        XCTAssertTrue(model.dailyWearShowsPersistFailure)
        XCTAssertEqual(model.wearCount(for: shirt.id), 0)
        let written = await inner.fetchWearEvents()
        XCTAssertTrue(written.isEmpty)

        model.reconcileDailyWearSuccessChrome()
        XCTAssertEqual(model.wearConfirmedMessage, DailyWearCopy.persistFailed)
    }

    @MainActor
    func testCorrectionPersistFailureRestoresPriorEvent() async throws {
        let shirt = disposableGarment(name: "Navy Oxford Shirt", slot: .top)
        let pants = disposableGarment(name: "Ink Trousers", slot: .bottom)
        let inner = InMemoryPersistenceStore(garments: [shirt, pants], sets: [], defaults: defaults)
        let prior = StubWearEvent(id: UUID(), garmentIds: [shirt.id], wornOn: Date())
        try await inner.saveWearEvent(prior)
        let store = FailingWearStore(inner: inner)
        store.failOnSaveIndex = 1
        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()
        XCTAssertEqual(model.wearCount(for: shirt.id), 1)

        let completion = await model.submitDailyWear(garmentIds: [pants.id])
        XCTAssertEqual(completion, .remain)
        XCTAssertEqual(model.wearConfirmedMessage, DailyWearCopy.persistFailed)
        XCTAssertTrue(model.dailyWearShowsPersistFailure)
        XCTAssertTrue(model.hasLoggedToday)
        let events = await inner.fetchWearEvents()
        let active = WearLogging.activeSameDay(events: events, day: Date())
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.id, prior.id)
        XCTAssertEqual(active.first?.garmentIds, [shirt.id])
        XCTAssertEqual(model.wearCount(for: shirt.id), 1)
        XCTAssertEqual(model.wearCount(for: pants.id), 0)
    }

    @MainActor
    func testBoardConfirmWearFailureDoesNotKeepSuccessMessage() async throws {
        let shirt = disposableGarment(name: "Navy Oxford Shirt", slot: .top)
        let store = InMemoryPersistenceStore(garments: [shirt], sets: [], defaults: defaults)
        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()
        model.wearConfirmedMessage = "Logged 1 READY garment as worn."
        model.reconcileDailyWearSuccessChrome()
        XCTAssertEqual(model.wearConfirmedMessage, DailyWearCopy.persistFailed)
        XCTAssertFalse(model.dailyWearShowsSuccessChrome)
    }

    // MARK: - Back navigation / end state

    @MainActor
    func testSuccessDisplayFollowsPersistedTodayNotStaleOutfit() async throws {
        let shirt = disposableGarment(name: "Navy Oxford Shirt", slot: .top)
        let pants = disposableGarment(name: "Ink Trousers", slot: .bottom)
        let store = InMemoryPersistenceStore(garments: [shirt, pants], sets: [], defaults: defaults)
        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()
        model.outfit = StubOutfit(
            id: UUID(),
            assignments: [
                StubOutfitAssignment(slot: .top, garmentId: shirt.id, gapReason: nil, isAnchor: true),
            ],
            rationaleSummary: "stale",
            offlineCached: false
        )
        let first = await model.submitDailyWear(garmentIds: [shirt.id])
        XCTAssertEqual(first, .popToWardrobe)
        XCTAssertEqual(model.wornGarmentsForDailyWearDisplay().map(\.id), [shirt.id])

        let corrected = await model.submitDailyWear(garmentIds: [pants.id])
        XCTAssertEqual(corrected, .popToWardrobe)
        XCTAssertEqual(model.wornGarmentsForDailyWearDisplay().map(\.id), [pants.id])
        XCTAssertNotEqual(model.wornGarmentsForDailyWearDisplay().map(\.id), [shirt.id])
        XCTAssertTrue(model.showsLoggedTodayRow)
        XCTAssertTrue(model.showsReplacingUnloggedSessionNote)
    }

    // MARK: - Relaunch, midnight, timezone

    @MainActor
    func testRelaunchRestoresLoggedTodayFromStore() async throws {
        let shirt = disposableGarment(name: "Navy Oxford Shirt", slot: .top)
        var directory: URL?
        var storeURL: URL?
        var first: ModelContainer?
        do {
            let created = try TestModelContainers.makeOnDiskTemp()
            directory = created.directory
            storeURL = created.storeURL
            first = created.container
            let store = SwiftDataPersistenceStore(container: created.container, defaults: defaults)
            try await store.saveGarment(shirt)
            let model = LoopDemoModel(store: store, preferences: defaults)
            await model.load()
            let completion = await model.submitDailyWear(garmentIds: [shirt.id])
            XCTAssertEqual(completion, .popToWardrobe)
            XCTAssertTrue(model.hasLoggedToday)
        }

        let restarted = try TestModelContainers.restart(storeURL: try XCTUnwrap(storeURL), releasing: try XCTUnwrap(first))
        first = nil
        let relaunched = SwiftDataPersistenceStore(container: restarted, defaults: defaults)
        let model = LoopDemoModel(store: relaunched, preferences: defaults)
        await model.load()
        XCTAssertTrue(model.hasLoggedToday)
        XCTAssertEqual(model.loggedTodaySnapshot()?.garments.map(\.id), [shirt.id])
        XCTAssertEqual(model.wearCount(for: shirt.id), 1)
        XCTAssertTrue(model.showsLoggedTodayRow)
        XCTAssertFalse(model.showsReturnToOutfitBanner)

        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    @MainActor
    func testLocalMidnightHidesTodayRowWithoutDeletingHistory() async throws {
        let shirt = disposableGarment(name: "Navy Oxford Shirt", slot: .top)
        let store = InMemoryPersistenceStore(garments: [shirt], sets: [], defaults: defaults)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: Date()))
        let event = StubWearEvent(id: UUID(), garmentIds: [shirt.id], wornOn: yesterday)
        try await store.saveWearEvent(event)

        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()
        XCTAssertNil(model.loggedTodayEvent(now: Date(), calendar: calendar))
        XCTAssertFalse(model.showsLoggedTodayRow)
        XCTAssertEqual(model.wearCount(for: shirt.id), 1)
        XCTAssertEqual(model.wearHistory(for: shirt.id).map(\.id), [event.id])
        let stored = await store.fetchWearEvents()
        XCTAssertEqual(WearLogging.loggedToday(events: stored, now: yesterday, calendar: calendar)?.id, event.id)
    }

    @MainActor
    func testTimezoneShiftDoesNotDropOrDuplicateHistoricalEvents() async throws {
        let shirt = disposableGarment(name: "Navy Oxford Shirt", slot: .top)
        let store = InMemoryPersistenceStore(garments: [shirt], sets: [], defaults: defaults)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let wornOn = try XCTUnwrap(utc.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 2)))
        let event = StubWearEvent(id: UUID(), garmentIds: [shirt.id], wornOn: wornOn)
        try await store.saveWearEvent(event)

        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))

        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()
        let all = await store.fetchWearEvents()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.id, event.id)
        XCTAssertEqual(all.first?.wornOn, wornOn)
        XCTAssertEqual(model.wearCount(for: shirt.id), 1)

        // Same instant is 20 Sep evening in LA and 21 Sep morning in Tokyo.
        let sept21NoonLA = try XCTUnwrap(
            losAngeles.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 12))
        )
        let sept21NoonTokyo = try XCTUnwrap(
            tokyo.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 12))
        )
        XCTAssertNil(WearLogging.loggedToday(events: all, now: sept21NoonLA, calendar: losAngeles))
        XCTAssertEqual(
            WearLogging.loggedToday(events: all, now: sept21NoonTokyo, calendar: tokyo)?.id,
            event.id
        )
        XCTAssertEqual(all.filter { !$0.isVoided }.count, 1)

        let tokyoRepeat = WearLogging.confirm(
            existing: all,
            garmentIds: [shirt.id],
            wornOn: sept21NoonTokyo,
            sourceOutfitId: nil,
            calendar: tokyo
        )
        XCTAssertFalse(tokyoRepeat.didWrite)
        let afterConfirm = await store.fetchWearEvents()
        XCTAssertEqual(afterConfirm.count, 1)
        XCTAssertEqual(afterConfirm.first?.id, event.id)
    }

    @MainActor
    func testNewOutfitDoesNotOverwriteLoggedHistory() async throws {
        let shirt = disposableGarment(name: "Navy Oxford Shirt", slot: .top)
        let pants = disposableGarment(name: "Ink Trousers", slot: .bottom)
        let store = InMemoryPersistenceStore(garments: [shirt, pants], sets: [], defaults: defaults)
        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()
        let completion = await model.submitDailyWear(garmentIds: [shirt.id])
        XCTAssertEqual(completion, .popToWardrobe)
        let loggedId = try XCTUnwrap(model.loggedTodayEvent()?.id)

        model.outfit = StubOutfit(
            id: UUID(),
            assignments: [
                StubOutfitAssignment(slot: .bottom, garmentId: pants.id, gapReason: nil, isAnchor: true),
            ],
            rationaleSummary: "new session",
            offlineCached: false
        )
        XCTAssertEqual(model.loggedTodayEvent()?.id, loggedId)
        XCTAssertEqual(model.wearCount(for: shirt.id), 1)
        XCTAssertTrue(model.showsLoggedTodayRow)
        XCTAssertTrue(model.showsReplacingUnloggedSessionNote)
        XCTAssertFalse(model.showsReturnToOutfitBanner)
    }

    // MARK: - Board primary / no silent replace

    @MainActor
    func testBoardPrimaryIsChangeWhatIWoreWhenLoggedToday() async throws {
        let shirt = disposableGarment(name: "Navy Oxford Shirt", slot: .top)
        let pants = disposableGarment(name: "Ink Trousers", slot: .bottom)
        let store = InMemoryPersistenceStore(garments: [shirt, pants], sets: [], defaults: defaults)
        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()

        XCTAssertEqual(model.boardWearPrimary, .wearingThis)
        XCTAssertEqual(model.boardWearPrimary.title, DailyWearCopy.wearingThis)
        XCTAssertTrue(model.boardWearPrimary.persistsFromBoard)

        let logged = await model.submitDailyWear(garmentIds: [shirt.id])
        XCTAssertEqual(logged, .popToWardrobe)
        model.outfit = StubOutfit(
            id: UUID(),
            assignments: [
                StubOutfitAssignment(slot: .bottom, garmentId: pants.id, gapReason: nil, isAnchor: true),
            ],
            rationaleSummary: "same-day new board",
            offlineCached: false
        )
        model.outfitWearable = true

        XCTAssertEqual(model.boardWearPrimary, .changeWhatIWore)
        XCTAssertEqual(model.boardWearPrimary.title, DailyWearCopy.changeWhatIWore)
        XCTAssertFalse(model.boardWearPrimary.persistsFromBoard)
        XCTAssertEqual(
            DailyWearBoardPrimary.resolve(hasLoggedToday: true),
            .changeWhatIWore
        )
    }

    @MainActor
    func testSecondBoardConfirmSameDayDoesNotReplaceEvent() async throws {
        let shirt = disposableGarment(name: "Navy Oxford Shirt", slot: .top)
        let pants = disposableGarment(name: "Ink Trousers", slot: .bottom)
        let store = InMemoryPersistenceStore(garments: [shirt, pants], sets: [], defaults: defaults)
        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()
        model.outfit = StubOutfit(
            id: UUID(),
            assignments: [
                StubOutfitAssignment(slot: .top, garmentId: shirt.id, gapReason: nil, isAnchor: true),
            ],
            rationaleSummary: "first",
            offlineCached: false
        )
        model.outfitWearable = true
        await model.wearingThisFromBoard()
        let prior = try XCTUnwrap(model.loggedTodayEvent())
        XCTAssertEqual(model.wearCount(for: shirt.id), 1)

        model.outfit = StubOutfit(
            id: UUID(),
            assignments: [
                StubOutfitAssignment(slot: .bottom, garmentId: pants.id, gapReason: nil, isAnchor: true),
            ],
            rationaleSummary: "second board",
            offlineCached: false
        )
        model.outfitWearable = true
        await model.wearingThisFromBoard()
        await model.confirmWear()
        let implicit = await model.submitDailyWear(garmentIds: nil)

        XCTAssertEqual(implicit, .remain)
        XCTAssertEqual(model.wearConfirmedMessage, DailyWearCopy.useCorrectionInstead)
        XCTAssertEqual(model.loggedTodayEvent()?.id, prior.id)
        XCTAssertEqual(model.loggedTodayEvent()?.garmentIds, [shirt.id])
        XCTAssertEqual(model.wearCount(for: shirt.id), 1)
        XCTAssertEqual(model.wearCount(for: pants.id), 0)
        let events = await store.fetchWearEvents()
        XCTAssertEqual(events.filter { !$0.isVoided }.count, 1)
        XCTAssertEqual(events.first { !$0.isVoided }?.id, prior.id)
    }

    // MARK: - Helpers

    private func disposableGarment(name: String, slot: StubSlot) -> StubGarment {
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
            formality: 3,
            warmth: 3,
            setId: nil,
            keepTogether: nil,
            lastWornOn: nil,
            daysSinceIntake: 0
        )
    }
}

/// Forwards to an in-memory store; can fail `saveWearEvent` after N successful saves.
private final class FailingWearStore: PersistenceStore, @unchecked Sendable {
    let inner: InMemoryPersistenceStore
    var failOnSaveIndex: Int?
    private var saveCount = 0

    init(inner: InMemoryPersistenceStore) {
        self.inner = inner
    }

    var backendName: String { inner.backendName }
    var dataGeneration: Int { inner.dataGeneration }

    func fetchGarments() async -> [StubGarment] { await inner.fetchGarments() }
    func saveGarment(_ garment: StubGarment) async throws { try await inner.saveGarment(garment) }
    func fetchOutfits() async -> [StubOutfit] { await inner.fetchOutfits() }
    func saveOutfit(_ outfit: StubOutfit) async throws { try await inner.saveOutfit(outfit) }
    func fetchWearEvents() async -> [StubWearEvent] { await inner.fetchWearEvents() }
    func fetchWearEvents(on day: Date) async -> [StubWearEvent] { await inner.fetchWearEvents(on: day) }
    func fetchWearAggregates() async -> WearAggregates { await inner.fetchWearAggregates() }
    func saveWearEvent(_ event: StubWearEvent) async throws {
        let index = saveCount
        saveCount += 1
        if failOnSaveIndex == index {
            throw NSError(domain: "DailyWearModelTests", code: 1)
        }
        try await inner.saveWearEvent(event)
    }
    func voidWearEvent(id: UUID) async throws { try await inner.voidWearEvent(id: id) }
    func fetchStyleProfile() async -> StubStyleProfile? { await inner.fetchStyleProfile() }
    func saveStyleProfile(_ profile: StubStyleProfile) async throws { try await inner.saveStyleProfile(profile) }
    func deleteGarment(id: UUID) async throws { try await inner.deleteGarment(id: id) }
    func clearWardrobeAndLooks() async throws { try await inner.clearWardrobeAndLooks() }
    func resetActiveStyleProfile() async throws -> StubStyleProfile { try await inner.resetActiveStyleProfile() }
    func fetchSets() async -> [StubSet] { await inner.fetchSets() }
    func beginCameraPending(jpegData: Data) async throws -> UUID { try await inner.beginCameraPending(jpegData: jpegData) }
    func abandonCameraPending(id: UUID) async throws { try await inner.abandonCameraPending(id: id) }
    func commitCameraPending(
        id: UUID,
        slot: StubSlot?,
        name: String?,
        color: StubColorPrimary?,
        pattern: String?,
        surface: String?,
        formality: Int?,
        warmth: Int?
    ) async throws -> StubGarment {
        try await inner.commitCameraPending(
            id: id,
            slot: slot,
            name: name,
            color: color,
            pattern: pattern,
            surface: surface,
            formality: formality,
            warmth: warmth
        )
    }

    func stagePhotoReplace(garmentId: UUID, jpegData: Data) async throws -> UUID {
        try await inner.stagePhotoReplace(garmentId: garmentId, jpegData: jpegData)
    }

    func abandonPhotoReplace(stagingId: UUID) async throws {
        try await inner.abandonPhotoReplace(stagingId: stagingId)
    }

    func replaceGarmentPhoto(garmentId: UUID, stagingId: UUID) async throws -> StubGarment {
        try await inner.replaceGarmentPhoto(garmentId: garmentId, stagingId: stagingId)
    }
}

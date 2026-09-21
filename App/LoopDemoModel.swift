import Foundation
import SwiftUI

/// Thin client loop driver — fixtures + in-memory only (no SwiftData / no live OpenRouter).
@MainActor
final class LoopDemoModel: ObservableObject {
    @Published var garments: [StubGarment] = []
    @Published var sets: [StubSet] = []
    @Published var selectedGarment: StubGarment?
    @Published var outfit: StubOutfit?
    @Published var swapAlternatives: [StubSwapAlternative] = []
    @Published var swapEmptyReason: String?
    @Published var isLoadingAlternatives: Bool = false
    @Published var swapSlot: StubSlot?
    @Published var isOffline: Bool = false
    @Published var occasion: DayOccasion = .workStandard
    @Published var temperatureBand: TempBand = .mild
    @Published var rain: Bool = false
    /// D-38 / P2-4 — context changed since last generate; board needs Update outfit.
    @Published var contextDirty: Bool = false
    @Published var showRetired: Bool {
        didSet { preferences.set(showRetired, forKey: "wardrobe.showRetired") }
    }
    var visibleGarments: [StubGarment] {
        garments.filter { showRetired || $0.availabilityToken != .retired }
    }
    @Published var isGenerating: Bool = false
    /// #112 — first build vs try-another vs context update (Cancel + copy).
    enum GenerateIntent: Equatable {
        case firstBuild
        case tryAnother
        case updateContext
    }
    @Published private(set) var generateIntent: GenerateIntent?
    @Published private(set) var generateProgressCopy: String?
    /// Secondary line under D-43 banner — unreachable vs service (AC-2).
    @Published var generateFailureSubtitle: String?
    /// GH #52 — generate failed; prior outfit kept. Not a wearable new result.
    @Published var generateFailureMessage: String? = nil
    @Published var generateFailureDetail: String? = nil
    /// True only after a successful online generate (or offline revalidated cache).
    @Published var outfitWearable: Bool = false
    @Published var isLoadingWardrobe: Bool = false
    @Published var wearConfirmedMessage: String?
    @Published var lastOutfitSelectedAt: Date?
    @Published var wearFlashToken: UUID?
    /// Outfit id last successfully logged — session flash only (#60). Per-day
    /// idempotency lives in `WearLogging` / the store, not this flag.
    @Published private(set) var lastWornOutfitId: UUID?
    @Published private(set) var wearCounts: [UUID: Int] = [:]
    @Published private(set) var wearEvents: [StubWearEvent] = []
    /// Max non-voided `wornOn` per garment from app WearEvents (#104).
    @Published private(set) var lastWornFromApp: [UUID: Date] = [:]
    @Published var styleProfile: StubStyleProfile?
    /// Transient confirmation (#105) — hosted in ContentView.
    @Published private(set) var activeToast: String?
    /// Undo swap from toast (#109).
    @Published private(set) var toastUndoAvailable: Bool = false
    var swapUndoAssignmentsSnapshot: [StubOutfitAssignment]?
    /// Swap sheet empty-state copy (inline, not global strip).
    @Published var swapSheetDetail: String?
#if DEBUG
    @Published private(set) var diagnosticLog: [String] = []
#endif
    /// D-20 / #95 — engine `noAlternativeReason` (or a client fallback) after Try another.
    @Published var noAlternativeReason: String?
    /// Brief “Updated” flash when Try another produced a different garment set.
    @Published var boardUpdatedFlash: Bool = false

    var toastDismissTask: Task<Void, Never>?
    var boardFlashDismissTask: Task<Void, Never>?
    /// Session garment-id sets already shown for the current starting item (max 10 sent).
    @Published private(set) var shownGarmentSets: [[UUID]] = []

    private var shownSetsAnchorId: UUID?
    private let preferences: UserDefaults
    private let store: PersistenceStore
    /// Board + wear state before an in-flight generate (#112 Cancel / failure restore).
    private var outfitSnapshotBeforeGenerate: StubOutfit?
    private var wearableSnapshotBeforeGenerate: Bool = false
    private var activeGenerateGeneration: UInt64 = 0
    /// Last store `dataGeneration` observed after a destructive op.
    private var observedDataGeneration: Int = 0
    /// In-flight swap request generation — late alternatives are dropped after delete/clear/reset.
    private var activeSwapGeneration: UInt64 = 0
    /// In-flight generate request. Cancel must abort the URLSession task (#162).
    private var generateFlight: OutfitEngineClient.EngineDataTask?
    /// Client timings against the 4 s / 8 s generation budgets (#158).
    private(set) var generationLatencySamples: [OutfitEngineClient.GenerationLatencySample] = []
    /// Fixture / intake last-worn stamps captured at load — never overwritten by app events.
    private var fixtureLastWornOn: [UUID: String] = [:]
    /// D-75 — one in-flight daily-wear persist at a time (rapid tap / retry).
    private var dailyWearWriteInFlight = false

    init(
        store: PersistenceStore = InMemoryPersistenceStore.shared,
        preferences: UserDefaults = .standard
    ) {
        self.store = store
        self.preferences = preferences
        self.showRetired = preferences.bool(forKey: "wardrobe.showRetired")
    }

    func load() async {
        isLoadingWardrobe = true
        defer { isLoadingWardrobe = false }
        // Do not rewrite availability / lastWornOn on every launch (#11 / #12).
        // Demo mix lives in fixtures/wardrobe/garments.json (single SoT).
        // App wear history overlays lastWornOn in memory only (#104).
        let all = await store.fetchGarments()
        garments = all
        fixtureLastWornOn = Dictionary(uniqueKeysWithValues: all.compactMap { g in
            g.lastWornOn.map { (g.id, $0) }
        })
        sets = await store.fetchSets()
        selectedGarment = all.first(where: { $0.isReady && $0.availability == "AVAILABLE" }) ?? all.first
        await loadOrSeedProfile()
        await refreshWearState()
        recordDiagnostic(
            all.isEmpty
                ? "No fixtures in bundle"
                : "Loaded \(all.count) fixture garments · \(sets.count) set(s)"
        )
    }

    private func loadOrSeedProfile() async {
        if let existing = await store.fetchStyleProfile() {
            styleProfile = existing
            return
        }
        if !SeedSuppression.shouldWriteAutomaticProfileSeed(
            hasExistingProfile: false,
            defaults: preferences
        ) {
            recordDiagnostic("Profile seed suppressed")
            return
        }
        guard var seed = FounderProfileSeedLoader.loadDraft() else {
            recordDiagnostic("No profile seed in bundle")
            return
        }
        // Always load as editable draft (confirmedAt nil) — M1-F01-07
        seed.confirmedAt = nil
        styleProfile = seed
        try? await store.saveStyleProfile(seed)
    }

    func updateProfile(_ profile: StubStyleProfile, announce: Bool = true) {
        var next = profile
        next.version = max(profile.version, (styleProfile?.version ?? 1))
        styleProfile = next
        Task { try? await store.saveStyleProfile(next) }
        if announce {
            showToast(next.isDraft ? "Profile draft saved" : "Profile updated")
        }
        recordDiagnostic(next.isDraft ? "Profile draft saved (unconfirmed)" : "Profile updated")
    }

    var wardrobeCoverage: WardrobeCoverage.Snapshot {
        WardrobeCoverage.evaluate(garments)
    }

    /// Demo launch args may confirm so engine evidence stays one-tap.
    func confirmProfileForDemoIfNeeded() {
        if styleProfile?.confirmedAt == nil {
            confirmProfile()
        }
    }

    func confirmProfile(_ editedProfile: StubStyleProfile? = nil) {
        guard var profile = editedProfile ?? styleProfile else { return }
        let wasDraft = profile.confirmedAt == nil
        profile.confirmedAt = Date()
        if wasDraft {
            profile.version = max(1, profile.version)
        } else {
            profile.version += 1
        }
        styleProfile = profile
        Task { try? await store.saveStyleProfile(profile) }
        showToast("Profile confirmed — outfits unlocked")
        recordDiagnostic("Style profile confirmed — outfit builds unlocked")
    }

    func markSummaryEdited(_ text: String) {
        guard var profile = styleProfile else { return }
        profile.summary = text
        profile.summaryUserOwned = true
        updateProfile(profile)
    }


    func select(_ garment: StubGarment) {
        selectedGarment = garment
    }

    /// Append or replace a live garment and persist it (user-added pieces, #97).
    func addGarment(_ garment: StubGarment) {
        if let idx = garments.firstIndex(where: { $0.id == garment.id }) {
            garments[idx] = garment
        } else {
            garments.append(garment)
        }
        if selectedGarment?.id == garment.id {
            selectedGarment = garment
        }
        if let last = garment.lastWornOn {
            fixtureLastWornOn[garment.id] = last
        }
        Task { try? await store.saveGarment(garmentForPersist(garment)) }
        recordDiagnostic("Added \(garment.displayName)")
    }

    func setFor(_ garment: StubGarment) -> StubSet? {
        guard let sid = garment.setId else {
            return sets.first(where: { $0.memberGarmentIds.contains(garment.id) })
        }
        return sets.first(where: { $0.id == sid })
    }

    func setPartners(for garment: StubGarment) -> [StubGarment] {
        guard let set = setFor(garment) else { return [] }
        return set.memberGarmentIds.compactMap { id in garments.first(where: { $0.id == id && $0.id != garment.id }) }
    }

    /// Persist a new draft immediately so Cancel on Finish details does not drop the photo (#98).
    @discardableResult
    func addDraftGarment(_ garment: StubGarment) async -> Bool {
        if let idx = garments.firstIndex(where: { $0.id == garment.id }) {
            garments[idx] = garment
        } else {
            garments.append(garment)
        }
        if selectedGarment?.id == garment.id {
            selectedGarment = garment
        }
        if let last = garment.lastWornOn {
            fixtureLastWornOn[garment.id] = last
        }
        do {
            try await store.saveGarment(garmentForPersist(garment))
            showToast("Draft saved")
            recordDiagnostic("Draft saved — finish details to use this")
            return true
        } catch {
            recordDiagnostic("Couldn’t save garment")
            return false
        }
    }

    /// D-73 — durable JPEG + PendingCapture; no garment until `commitCameraPending`.
    func beginCameraPending(jpegData: Data) async throws -> CameraPending {
        let id = try await store.beginCameraPending(jpegData: jpegData)
        return CameraPending(id: id, imagePath: UserGarmentPhotoStore.pendingPhotoPath(for: id))
    }

    /// D-73 — drop the pending row and file. Writes no garment. Idempotent after commit.
    func abandonCameraPending(id: UUID) async {
        try? await store.abandonCameraPending(id: id)
    }

    /// D-73 — one garment with an explicit slot via the persist store. Never defaults Top.
    @discardableResult
    func commitCameraPending(id: UUID, fields: CameraIntakeCommitFields) async -> Bool {
        do {
            let trimmed = fields.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let colorOk = FinishDetailsColorDraft.hasSwatchIdentity(fields.color)
            let garment = try await store.commitCameraPending(
                id: id,
                slot: fields.slot,
                name: trimmed.isEmpty ? nil : trimmed,
                color: colorOk ? fields.color : nil,
                pattern: fields.pattern.isEmpty ? nil : fields.pattern,
                surface: fields.surface.isEmpty ? nil : fields.surface,
                formality: fields.formality,
                warmth: fields.warmth
            )
            if let idx = garments.firstIndex(where: { $0.id == garment.id }) {
                garments[idx] = garment
            } else {
                garments.append(garment)
            }
            if selectedGarment?.id == garment.id {
                selectedGarment = garment
            }
            if fields.purchasePrice != nil || fields.priorWearBucket != nil || fields.purchaseDate != nil {
                _ = await savePurchaseInfo(
                    id: garment.id,
                    price: fields.purchasePrice,
                    currency: fields.purchaseCurrency,
                    purchaseDate: fields.purchaseDate,
                    priorWearBucket: fields.priorWearBucket
                )
            }
            recordDiagnostic("Camera garment saved — \(garment.displayName)")
            return true
        } catch {
            recordDiagnostic("Couldn’t save camera garment")
            return false
        }
    }

    @discardableResult
    func savePurchaseInfo(
        id: UUID,
        price: Decimal?,
        currency: String?,
        purchaseDate: Date?,
        priorWearBucket: String?
    ) async -> Bool {
        guard var g = garments.first(where: { $0.id == id }) else { return false }
        if let price, price <= 0 { return false }
        let storedPrice = StubGarment.persistedPurchasePrice(price)
        g.purchasePrice = storedPrice
        g.purchaseCurrency = storedPrice == nil ? nil : (currency ?? CostPerWearCopy.deviceCurrency)
        g.purchaseDate = purchaseDate
        g.priorWearBucket = priorWearBucket
        if let priorWearBucket, let bucket = PriorWearBucket(rawValue: priorWearBucket) {
            g.priorWearEstimate = bucket.midpoint
        } else {
            g.priorWearEstimate = nil
        }
        if let idx = garments.firstIndex(where: { $0.id == id }) {
            garments[idx] = g
        }
        if selectedGarment?.id == id {
            selectedGarment = g
        }
        do {
            try await store.saveGarment(garmentForPersist(g))
            showToast(storedPrice == nil ? "Price cleared" : "Price saved")
            return true
        } catch {
            recordDiagnostic("Couldn’t save price")
            return false
        }
    }

    func setAvailability(_ id: UUID, _ raw: String) {
        guard let idx = garments.firstIndex(where: { $0.id == id }) else { return }
        garments[idx].availability = raw
        let g = garments[idx]
        if selectedGarment?.id == id {
            selectedGarment = g
        }
        Task { try? await store.saveGarment(garmentForPersist(g)) }
        let token = AvailabilityToken(raw: raw)
        showToast("Marked \(token.accessibilityName)")
        bumpLightHaptic()
        recordDiagnostic("\(g.displayName) → \(raw)")
    }

    func cycleAvailability(_ id: UUID) {
        guard let idx = garments.firstIndex(where: { $0.id == id }) else { return }
        let order = AvailabilityToken.allCases
        let current = garments[idx].availabilityToken
        let next = order[((order.firstIndex(of: current) ?? 0) + 1) % order.count]
        setAvailability(id, next.rawValue)
    }

    /// Sync gate before navigating to the board (#112 — build → board immediately).
    func validateBuildPreconditions() -> Bool {
        guard selectedGarment != nil else { return false }
        guard validateBuildPreconditions(setFailureMessage: true) else { return false }
        return true
    }

    private func validateBuildPreconditions(setFailureMessage: Bool) -> Bool {
        guard let anchor = selectedGarment else { return false }
        guard anchor.isReady else {
            if setFailureMessage {
                applyPreGenerateFailure(message: "Finish details before building an outfit")
            }
            return false
        }
        guard anchor.availability == "AVAILABLE" else {
            if setFailureMessage {
                applyPreGenerateFailure(message: "That starting item isn't available")
            }
            return false
        }
        if styleProfile?.confirmedAt == nil {
            if setFailureMessage {
                applyPreGenerateFailure(message: "Confirm your style profile before building")
            }
            return false
        }
        return true
    }

    /// Abandon in-flight generate; restore snapshot when Try another / Update / Retry had a prior board.
    func cancelGeneration() {
        guard isGenerating else { return }
        generateFlight?.cancel()
        generateFlight = nil
        activeGenerateGeneration += 1
        isGenerating = false
        generateIntent = nil
        generateProgressCopy = nil
        if let snap = outfitSnapshotBeforeGenerate {
            outfit = snap
            outfitWearable = wearableSnapshotBeforeGenerate
        } else {
            outfit = nil
            outfitWearable = false
        }
        outfitSnapshotBeforeGenerate = nil
        generateFailureMessage = nil
        generateFailureSubtitle = nil
        generateFailureDetail = nil
        recordDiagnostic("Generate cancelled")
    }

    /// Inline why for disabled Wearing this (AC-4).
    func wearDisabledReason() -> String? {
        guard !outfitWearable else { return nil }
        if isGenerating {
            return "Wait until the outfit finishes building"
        }
        if contextDirty {
            return "Update outfit for this weather and occasion first"
        }
        if let outfit {
            for a in outfit.assignments {
                guard let gid = a.garmentId else { continue }
                guard let g = garments.first(where: { $0.id == gid }) else {
                    return "This outfit is out of date — a piece isn't available"
                }
                if !g.isReady {
                    return "Finish details on \(g.displayName) first"
                }
                if g.availability != "AVAILABLE" {
                    return "This outfit is out of date — \(g.displayName) isn't available"
                }
            }
        }
        if generateFailureMessage != nil, outfit == nil {
            return "Build a valid outfit first"
        }
        return "This outfit isn't ready to log yet"
    }

    static func skeletonOutfit(anchor: StubGarment) -> StubOutfit {
        var assignments: [StubOutfitAssignment] = [
            .init(slot: anchor.slot, garmentId: anchor.id, gapReason: nil, isAnchor: true),
        ]
        for slot in StubSlot.wearingOrder where slot != anchor.slot {
            assignments.append(
                StubOutfitAssignment(
                    slot: slot,
                    garmentId: nil,
                    gapReason: StubOutfitAssignment.skeletonMarker,
                    isAnchor: false
                )
            )
        }
        return StubOutfit(
            id: UUID(),
            assignments: assignments,
            rationaleSummary: "",
            offlineCached: false
        )
    }

    private func beginOnlineGeneration(
        intent: GenerateIntent,
        anchor: StubGarment,
        priorBoard: StubOutfit?,
        priorWearable: Bool
    ) {
        let realPrior = priorBoard.flatMap { board in
            board.assignments.contains(where: { $0.isSkeletonPlaceholder }) ? nil : board
        }
        if let realPrior {
            outfitSnapshotBeforeGenerate = realPrior
            wearableSnapshotBeforeGenerate = priorWearable
        } else {
            outfitSnapshotBeforeGenerate = nil
            wearableSnapshotBeforeGenerate = false
        }
        outfit = Self.skeletonOutfit(anchor: anchor)
        outfitWearable = false
        generateIntent = intent
        generateProgressCopy = progressCopy(for: intent, anchor: anchor)
        generateFailureMessage = nil
        generateFailureSubtitle = nil
        generateFailureDetail = nil
        isGenerating = true
        activeGenerateGeneration += 1
    }

    private func progressCopy(for intent: GenerateIntent, anchor: StubGarment) -> String {
        switch intent {
        case .firstBuild:
            return DressingCopy.buildingAround(anchor.displayName)
        case .tryAnother:
            return DressingCopy.tryingAnotherAround(anchor.displayName)
        case .updateContext:
            return DressingCopy.updatingForContext(
                occasion: occasion,
                rain: rain,
                temperature: temperatureBand
            )
        }
    }

    private func applyGenerateFailure(_ error: Error, generation: UInt64) {
        guard generation == activeGenerateGeneration, isCurrentStoreGeneration() else { return }
        let detail = DressingCopy.generateFailureDetail(from: error)
        if let snap = outfitSnapshotBeforeGenerate {
            outfit = snap
            outfitWearable = wearableSnapshotBeforeGenerate
            generateFailureMessage = DressingCopy.generateFailureWithPriorBanner
            generateFailureSubtitle = detail.user
        } else {
            outfit = nil
            outfitWearable = false
            generateFailureMessage = detail.user
            generateFailureSubtitle = nil
        }
        generateFailureDetail = detail.diagnostic
        outfitSnapshotBeforeGenerate = nil
        generateIntent = nil
        generateProgressCopy = nil
        recordDiagnostic("Generate failure (diagnostic): \(detail.diagnostic)")
    }

    private func applyPreGenerateFailure(message: String) {
        generateFailureMessage = message
        generateFailureSubtitle = nil
        generateFailureDetail = nil
        outfitWearable = false
    }

    /// Online: local S1→S2→builder via :8787. Offline: last valid / clear failure (GH #52).
    /// Returns false on failure without replacing a prior valid outfit with synthetic filler.
    /// - Parameter excludeShown: Try another — send `options.excludeGarmentSets` (D-20 / #95).
    @discardableResult
    func buildDemoOutfit(
        preserveLocks: Bool = true,
        excludeShown: Bool = false,
        intent: GenerateIntent? = nil
    ) async -> Bool {
        clearWearFlash()
        boardUpdatedFlash = false
        guard let anchor = selectedGarment else { return false }
        guard validateBuildPreconditions(setFailureMessage: true) else { return false }

        if isOffline {
            return applyOfflineOutfit(anchor: anchor)
        }

        let resolvedIntent: GenerateIntent = intent ?? (excludeShown ? .tryAnother : .firstBuild)
        let boardBefore = outfit
        let wearableBefore = outfitWearable
        let priorLocks: [StubOutfitAssignment]
        if preserveLocks, let boardBefore,
           !boardBefore.assignments.contains(where: { $0.isSkeletonPlaceholder }) {
            priorLocks = boardBefore.assignments.filter { $0.isLocked && !$0.isAnchor }
        } else {
            priorLocks = []
        }

        if !isGenerating {
            beginOnlineGeneration(
                intent: resolvedIntent,
                anchor: anchor,
                priorBoard: boardBefore,
                priorWearable: wearableBefore
            )
        }
        let generation = activeGenerateGeneration
        let flight = OutfitEngineClient.EngineDataTask()
        generateFlight = flight
        let started = Date()
        defer {
            if generateFlight === flight { generateFlight = nil }
            if generation == activeGenerateGeneration {
                isGenerating = false
                generateIntent = nil
                generateProgressCopy = nil
            }
        }

        do {
            if shownSetsAnchorId != anchor.id {
                resetShownOutfitExclusions()
                shownSetsAnchorId = anchor.id
            }
            let payloadGarments = garmentsForEngine(including: anchor)
            let response = try await OutfitEngineClient.generate(
                garments: payloadGarments,
                sets: sets,
                anchorId: anchor.id,
                lockedAssignments: priorLocks,
                occasion: occasion.apiValue,
                occasionFormality: occasion.occasionFormality,
                temperatureBand: temperatureBand.apiValue,
                precipitation: rain,
                excludeGarmentSets: excludeShown ? excludeSetsForTryAnother() : [],
                flight: flight
            )
            guard generation == activeGenerateGeneration else { return false }
            guard isCurrentStoreGeneration() else { return false }
            recordGenerationLatency(milliseconds: elapsedMilliseconds(since: started), outcome: "success")

            var built = OutfitEngineClient.mapToStubOutfit(response, anchorId: anchor.id)
            if preserveLocks {
                built = Self.reapplyLocks(built, priorLocks: priorLocks, anchorId: anchor.id)
            }
            let snapshotIds = outfitSnapshotBeforeGenerate.map { Set(Self.garmentIds(of: $0)) } ?? []
            let newIds = Set(Self.garmentIds(of: built))
            let sameSet = !snapshotIds.isEmpty && newIds == snapshotIds
            let engineReason = response.noAlternativeReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            contextDirty = false
            generateFailureMessage = nil
            generateFailureSubtitle = nil
            generateFailureDetail = nil

            if excludeShown && (!engineReason.isEmpty || sameSet) {
                noAlternativeReason = DressingCopy.noAlternative(engineReason.isEmpty ? nil : engineReason)
                boardUpdatedFlash = false
                let snap = outfitSnapshotBeforeGenerate
                let wearable = wearableSnapshotBeforeGenerate
                outfitSnapshotBeforeGenerate = nil
                if let snap {
                    outfit = snap
                    outfitWearable = wearable
                } else {
                    outfit = built
                    outfitWearable = true
                    recordShown(built)
                }
                return true
            }

            noAlternativeReason = nil
            outfit = built
            outfitWearable = true
            outfitSnapshotBeforeGenerate = nil
            recordShown(built)
            if excludeShown {
                boardUpdatedFlash = true
                scheduleBoardUpdatedFlashDismiss()
            }
            return true
        } catch {
            let elapsed = elapsedMilliseconds(since: started)
            guard generation == activeGenerateGeneration, isCurrentStoreGeneration() else {
                recordGenerationLatency(milliseconds: elapsed, outcome: "cancelled")
                return false
            }
            recordGenerationLatency(milliseconds: elapsed, outcome: "failure")
            let hadPriorBoard = outfitSnapshotBeforeGenerate != nil
            applyGenerateFailure(error, generation: generation)
            recordDiagnostic(
                hadPriorBoard
                    ? "Generate failed — prior outfit restored"
                    : "Generate failed — retry or pick another starting item"
            )
            return false
        }
    }

    /// Try another — exclude every set already shown this starting-item session (#95).
    @discardableResult
    func tryAnotherOutfit() async -> Bool {
        await buildDemoOutfit(preserveLocks: true, excludeShown: true, intent: .tryAnother)
    }

    /// Include the selected starting item even if it is not yet in `garments` (#97).
    private func garmentsForEngine(including anchor: StubGarment) -> [StubGarment] {
        if garments.contains(where: { $0.id == anchor.id }) { return garments }
        return garments + [anchor]
    }

    static func garmentIds(of outfit: StubOutfit) -> [UUID] {
        outfit.assignments.compactMap(\.garmentId)
    }

    private func recordShown(_ outfit: StubOutfit) {
        let ids = Self.garmentIds(of: outfit)
        guard !ids.isEmpty else { return }
        let set = Set(ids)
        if !shownGarmentSets.contains(where: { Set($0) == set }) {
            shownGarmentSets.append(ids)
        }
    }

    private func excludeSetsForTryAnother() -> [[UUID]] {
        var sets = shownGarmentSets
        if let current = outfit {
            let currentIds = Self.garmentIds(of: current)
            if !currentIds.isEmpty, !sets.contains(where: { Set($0) == Set(currentIds) }) {
                sets.append(currentIds)
            }
        }
        return Array(sets.suffix(OutfitEngineClient.excludeGarmentSetsCap))
    }

    /// Reset when the starting item changes. Context Update also resets (new occasion/weather session).
    func resetShownOutfitExclusions() {
        shownGarmentSets = []
        shownSetsAnchorId = nil
        noAlternativeReason = nil
        boardUpdatedFlash = false
    }

    @discardableResult
    private func applyOfflineOutfit(anchor: StubGarment) -> Bool {
        generateFailureDetail = nil
        if var existing = outfit {
            existing.offlineCached = true
            existing.rationaleSummary = "You’re offline. This is the last outfit for this starting item — still available pieces only."
            outfit = existing
            generateFailureMessage = nil
            outfitWearable = true  // D-24 cached/revalidated path
            contextDirty = false
            recordDiagnostic("Offline — showing your last outfit")
            return true
        }
        generateFailureMessage = "You’re offline and there’s no saved outfit for this starting item"
        generateFailureDetail = nil
        outfitWearable = false
        recordDiagnostic("Offline — no saved outfit yet")
        return false
    }

    func alternatives(for slot: StubSlot) async {
        swapSlot = slot
        swapEmptyReason = nil
        swapAlternatives = []
        swapSheetDetail = nil
        if isOffline {
            swapSheetDetail = DressingCopy.swapOfflineMessage
            return
        }
        guard let outfit else {
            swapSheetDetail = "Build an outfit first."
            return
        }
        if let a = outfit.assignments.first(where: { $0.slot == slot }), a.isLocked || a.isAnchor {
            swapEmptyReason = "LOCK_FIXED"
            swapSheetDetail = DressingCopy.swapEmptyState(code: "LOCK_FIXED").message
            return
        }
        // A generation shortlist is not swap-validated; use the D-33 endpoint.
        activeSwapGeneration += 1
        let generation = activeSwapGeneration
        isLoadingAlternatives = true
        defer {
            if generation == activeSwapGeneration {
                isLoadingAlternatives = false
            }
        }

        do {
            let response = try await OutfitEngineClient.fetchAlternatives(
                slot: slot,
                outfit: outfit,
                garments: selectedGarment.map { garmentsForEngine(including: $0) } ?? garments,
                sets: sets,
                occasion: occasion.apiValue,
                occasionFormality: occasion.occasionFormality,
                temperatureBand: temperatureBand.apiValue,
                precipitation: rain
            )
            guard generation == activeSwapGeneration, isCurrentStoreGeneration() else { return }
            let mapped = OutfitEngineClient.mapAlternatives(response, garments: garments)
            swapAlternatives = mapped.alts
            swapEmptyReason = mapped.emptyReason
            if let reason = mapped.emptyReason, mapped.alts.isEmpty {
                swapSheetDetail = DressingCopy.swapEmptyState(code: reason).message
            } else {
                swapSheetDetail = nil
                recordDiagnostic("\(mapped.alts.count) alternatives")
            }
        } catch {
            guard generation == activeSwapGeneration, isCurrentStoreGeneration() else { return }
            let used = Set(outfit.assignments.compactMap(\.garmentId))
            let alts = garments.filter {
                $0.slot == slot && $0.isReady && $0.availability == "AVAILABLE" && !used.contains($0.id)
                    && $0.id != selectedGarment?.id
            }
            .prefix(5)
            .map {
                StubSwapAlternative(
                    id: $0.id,
                    garment: $0,
                    reason: "Stub fallback — engine unreachable",
                    score: nil,
                    setPartnerIds: []
                )
            }
            swapAlternatives = Array(alts)
            swapEmptyReason = nil
            swapSheetDetail = "Couldn’t rank swaps. Try again."
            recordDiagnostic("Couldn’t rank swaps — showing local suggestions.")
        }
    }

    /// Assignment for the slot being swapped (header / empty gap copy).
    func swapSlotAssignment() -> StubOutfitAssignment? {
        guard let slot = swapSlot, let outfit else { return nil }
        return outfit.assignments.first(where: { $0.slot == slot })
    }

    func garment(in assignment: StubOutfitAssignment) -> StubGarment? {
        guard let gid = assignment.garmentId else { return nil }
        return garments.first(where: { $0.id == gid })
    }

    func applySwap(_ alt: StubSwapAlternative) {
        clearWearFlash()
        guard var outfit, let slot = swapSlot else { return }
        let undoSnapshot = outfit.assignments
        if let idx = outfit.assignments.firstIndex(where: { $0.slot == slot }) {
            guard !outfit.assignments[idx].isLocked, !outfit.assignments[idx].isAnchor else {
                recordDiagnostic("\(slot.displayLabel) is locked — unlock to swap")
                return
            }
            outfit.assignments[idx].garmentId = alt.garment.id
            outfit.assignments[idx].gapReason = nil
            outfit.assignments[idx].isLocked = true
        }
        for partnerId in alt.setPartnerIds {
            guard let partner = garments.first(where: { $0.id == partnerId }) else { continue }
            if let idx = outfit.assignments.firstIndex(where: { $0.slot == partner.slot }) {
                if outfit.assignments[idx].isLocked || outfit.assignments[idx].isAnchor { continue }
                outfit.assignments[idx].garmentId = partner.id
                outfit.assignments[idx].gapReason = nil
            } else {
                outfit.assignments.append(
                    StubOutfitAssignment(slot: partner.slot, garmentId: partner.id, gapReason: nil, isAnchor: false, isLocked: false)
                )
            }
        }
        outfit.rationaleSummary = "Updated after swap."
        self.outfit = outfit
        showSwapAppliedToast("Swapped to \(alt.garment.displayName)", undoSnapshot: undoSnapshot)
        recordDiagnostic("Swapped \(slot.displayLabel) → \(alt.garment.displayName)")
    }

    /// Top-ranked alternative for **Suggest for me** (#109).
    func applyTopSwapSuggestion() {
        guard let top = swapAlternatives.first else { return }
        applySwap(top)
    }

    /// Explicit Keep / Unlock (GH #51 / #61). Prefer `assignmentId` when several accessories share a slot.
    func setAssignmentLocked(slot: StubSlot, locked: Bool, assignmentId: UUID? = nil) {
        guard var outfit else { return }
        let idx: Int?
        if let assignmentId {
            idx = outfit.assignments.firstIndex(where: { $0.id == assignmentId })
        } else {
            idx = outfit.assignments.firstIndex(where: { $0.slot == slot })
        }
        guard let idx else { return }
        guard !outfit.assignments[idx].isAnchor else {
            recordDiagnostic("Starting item stays fixed — change starting item to replace it")
            return
        }
        outfit.assignments[idx].isLocked = locked
        self.outfit = outfit
        let name = slot.displayLabel
        showToast(locked ? "Kept \(name)" : "Unlocked \(name)")
        recordDiagnostic(
            locked
                ? "Kept \(name) — survives Try another"
                : "Unlocked \(name) — swap again anytime"
        )
    }

    /// Explicit Change anchor — new generation; clears prior locks (F05-04).
    /// On failure restores `priorOutfit` and does not keep a synthetic board (#52 / #53).
    @discardableResult
    func changeAnchor(to garment: StubGarment, priorOutfit: StubOutfit? = nil) async -> Bool {
        clearWearFlash()
        resetShownOutfitExclusions()
        let fallback = priorOutfit ?? outfit
        select(garment)
        let ok = await buildDemoOutfit(preserveLocks: false)
        if !ok {
            outfit = fallback
            if generateFailureMessage == nil {
                generateFailureMessage = "Couldn’t change starting item"
            }
            recordDiagnostic("Couldn’t change starting item — restored previous outfit")
            return false
        }
        showToast("Starting item is now \(garment.displayName)")
        return true
    }



    func wearingThisFromBoard() async {
        guard outfitWearable, outfit != nil else {
            recordDiagnostic("Can’t log wear — outfit isn’t a validated result")
            return
        }
        if hasLoggedToday {
            wearConfirmedMessage = DailyWearCopy.useCorrectionInstead
            recordDiagnostic("Wear blocked — already logged today")
            return
        }
        lastOutfitSelectedAt = Date()
        _ = await submitDailyWear(garmentIds: nil)
    }

    func wearCount(for id: UUID) -> Int {
        wearCounts[id] ?? 0
    }

    /// Today's active event matches the board's READY garment set.
    var didLogCurrentOutfitToday: Bool {
        let ids = Set(readyOutfitGarmentIds())
        guard !ids.isEmpty else { return false }
        return WearLogging.activeSameDay(events: wearEvents, day: Date())
            .contains { Set($0.garmentIds) == ids }
    }

    var canUndoTodayWear: Bool {
        !WearLogging.activeSameDay(events: wearEvents, day: Date()).isEmpty
    }

    /// GH #60 — flash belongs only to the just-confirmed session. Per-day
    /// idempotency is store-backed (`WearLogging`), so clearing this flag
    /// cannot double-count after Done → Return.
    func clearWearFlash() {
        wearFlashToken = nil
        // outfit.id often survives swap; must clear so the session flag
        // does not false-block a swapped look (#60).
        lastWornOutfitId = nil
    }

    /// Compact wear line — single SoT from confirmed WearEvents (demo-ux-polish P0-2 / PRD §7.8).
    func wearSummaryLine(for id: UUID) -> String {
        let n = wearCount(for: id)
        if n <= 0 { return "Not worn yet" }
        return "\(n) wear\(n == 1 ? "" : "s") in the app"
    }

    /// Human last-worn line: app events win; fixture estimate only when none (#104).
    func lastWornLine(for id: UUID) -> String? {
        DressingCopy.lastWornLine(
            appDate: lastWornFromApp[id],
            fixtureISO: lastWornFromApp[id] == nil ? fixtureLastWornOn[id] : nil
        )
    }

    /// P0-1 — fill missing readiness fields; promote to READY when all five present.
    @discardableResult
    /// Apply readiness fields. When `requireComplete` is true, all five must be present
    /// or the save fails (GH #55 / D-23 — no silent defaults). Partial saves stay DRAFT.
    func completeReadiness(
        id: UUID,
        slot: StubSlot? = nil,
        displayName: String? = nil,
        displayNameIsUserSet: Bool = false,
        color: StubColorPrimary,
        pattern: String,
        surface: String,
        formality: Int?,
        warmth: Int?,
        purchasePrice: Decimal? = nil,
        purchaseCurrency: String? = nil,
        purchaseDate: Date? = nil,
        priorWearBucket: String? = nil,
        applyPurchase: Bool = false,
        requireComplete: Bool = true
    ) async -> Bool {
        guard var g = garments.first(where: { $0.id == id }) else { return false }
        let previous = g
        let colorOk = FinishDetailsColorDraft.hasSwatchIdentity(color)
        if requireComplete {
            guard colorOk, !pattern.isEmpty, !surface.isEmpty, formality != nil, warmth != nil else {
                recordDiagnostic("Finish every required detail")
                return false
            }
        }
        if let slot {
            g.slot = slot
            g.attributeSource["slot"] = "USER"
        }
        if let displayName {
            let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                g.displayName = StubGarment.untitledName(for: g.slot)
                g.displayNameSource = "DERIVED"
            } else {
                g.displayName = displayName
                g.displayNameSource = displayNameIsUserSet ? "USER" : "DERIVED"
            }
        }
        if colorOk {
            g.colorPrimary = color
            g.attributeSource["color"] = "USER"
        } else if !requireComplete {
            g.colorPrimary = nil
            g.attributeSource["color"] = "USER"
        }
        if !pattern.isEmpty {
            g.pattern = pattern
            g.attributeSource["pattern"] = "USER"
        } else if !requireComplete {
            g.pattern = nil
            g.attributeSource["pattern"] = "USER"
        }
        if !surface.isEmpty {
            g.surface = surface
            g.attributeSource["surface"] = "USER"
        } else if !requireComplete {
            g.surface = nil
            g.attributeSource["surface"] = "USER"
        }
        if let formality {
            g.formality = formality
            g.attributeSource["formality"] = "USER"
        } else if !requireComplete {
            g.formality = nil
            g.attributeSource["formality"] = "USER"
        }
        if let warmth {
            g.warmth = warmth
            g.attributeSource["warmth"] = "USER"
        } else if !requireComplete {
            g.warmth = nil
            g.attributeSource["warmth"] = "USER"
        }
        if applyPurchase {
            if let purchasePrice, purchasePrice <= 0 { return false }
            let storedPrice = StubGarment.persistedPurchasePrice(purchasePrice)
            g.purchasePrice = storedPrice
            g.purchaseCurrency = storedPrice == nil ? nil : (purchaseCurrency ?? CostPerWearCopy.deviceCurrency)
            g.purchaseDate = purchaseDate
            g.priorWearBucket = priorWearBucket
            if let priorWearBucket, let bucket = PriorWearBucket(rawValue: priorWearBucket) {
                g.priorWearEstimate = bucket.midpoint
            } else {
                g.priorWearEstimate = nil
            }
        }
        let readyNow = colorOk
            && !(g.pattern ?? "").isEmpty
            && !(g.surface ?? "").isEmpty
            && g.formality != nil
            && g.warmth != nil
        if readyNow {
            g.readiness = .ready
            // D-31: derived untitled names regenerate; user-set names are never overwritten.
            if g.displayNameSource != "USER", g.displayName.lowercased().hasPrefix("untitled") {
                let colorName = color.name ?? color.family ?? ""
                g.displayName = "\(colorName) \(g.slot.displayLabel)".trimmingCharacters(in: .whitespaces)
                g.displayNameSource = "DERIVED"
            }
        } else {
            // Stay draft — never promote on partial fill (#55)
            if g.readiness == .ready {
                g.readiness = .draft
            }
            if g.displayNameSource != "USER", g.displayName.lowercased().hasPrefix("untitled") {
                g.displayName = StubGarment.untitledName(for: g.slot)
            }
        }
        if let idx = garments.firstIndex(where: { $0.id == id }) {
            garments[idx] = g
        }
        if selectedGarment?.id == id {
            selectedGarment = g
        }
        do {
            try await store.saveGarment(garmentForPersist(g))
            let slotChanged = g.slot != previous.slot
            let readinessChanged = g.colorPrimary != previous.colorPrimary
                || g.pattern != previous.pattern
                || g.surface != previous.surface
                || g.formality != previous.formality
                || g.warmth != previous.warmth
            // D-72 / #120: drop stale generate after a real edit. cancelGeneration
            // is a no-op when idle; the extra generation bump still rejects late persist.
            if slotChanged || readinessChanged {
                invalidateInFlightEngineWork()
            }
            if slotChanged, let board = outfit, Self.garmentIds(of: board).contains(id) {
                clearBoardAndSwapState()
            }
            showToast(g.isReady ? "Details saved — ready to use" : "Draft saved")
            return true
        } catch {
            recordDiagnostic("Couldn’t save details")
            return false
        }
    }

    func confirmWear(garmentIds: [UUID]? = nil) async {
        if hasLoggedToday {
            wearConfirmedMessage = DailyWearCopy.useCorrectionInstead
            recordDiagnostic("Wear blocked — already logged today")
            return
        }
        let ids: [UUID]
        let sourceOutfitId: UUID?
        if let garmentIds {
            let allowed = Set(garments.filter { $0.isReady }.map(\.id))
            ids = garmentIds.filter { allowed.contains($0) }
            sourceOutfitId = nil
            if ids.isEmpty {
                wearConfirmedMessage = "Blocked — finish details before logging wear."
                recordDiagnostic("Wear blocked (draft)")
                return
            }
        } else {
            guard outfit != nil else { return }
            ids = readyOutfitGarmentIds()
            sourceOutfitId = outfit?.id
        }
        let existing = await store.fetchWearEvents(on: Date())
        let result = WearLogging.confirm(
            existing: existing,
            garmentIds: ids,
            wornOn: Date(),
            sourceOutfitId: sourceOutfitId
        )
        for voided in result.voided {
            try? await store.saveWearEvent(voided)
        }
        if let event = result.event {
            try? await store.saveWearEvent(event)
            lastWornOutfitId = event.sourceOutfitId ?? outfit?.id
        }
        if let outfit {
            _ = await persistOutfitIfGenerationCurrent(outfit, capturedDataGeneration: observedDataGeneration)
        }
        await refreshWearState()
        wearConfirmedMessage = result.message
        recordDiagnostic(result.statusLine)
        if result.didWrite, sourceOutfitId != nil {
            notifyWearLoggedForToday()
        }
    }

    func voidWear(id: UUID) async {
        do {
            try await store.voidWearEvent(id: id)
        } catch {
            recordDiagnostic("Couldn’t void wear")
        }
        await refreshWearState()
    }

    /// Non-voided wears that include this garment, newest first (D-72).
    func wearHistory(for garmentId: UUID) -> [StubWearEvent] {
        wearEvents
            .filter { !$0.isVoided && $0.garmentIds.contains(garmentId) }
            .sorted { $0.wornOn > $1.wornOn }
    }

    /// Full history including voided events, newest first. UI marks voided rows.
    func wearHistoryAll(for garmentId: UUID) -> [StubWearEvent] {
        wearEvents
            .filter { $0.garmentIds.contains(garmentId) }
            .sorted { $0.wornOn > $1.wornOn }
    }

    /// Detail section: last five non-voided wears.
    func recentWearHistory(for garmentId: UUID, limit: Int = 5) -> [StubWearEvent] {
        Array(wearHistory(for: garmentId).prefix(limit))
    }

    func undoTodayWear() async {
        let existing = await store.fetchWearEvents(on: Date())
        guard let result = WearLogging.undoToday(events: existing) else {
            wearConfirmedMessage = "Nothing to undo"
            recordDiagnostic("Nothing to undo")
            return
        }
        for ev in result.updated {
            try? await store.saveWearEvent(ev)
        }
        lastWornOutfitId = nil
        await refreshWearState()
        wearConfirmedMessage = result.message
        recordDiagnostic(result.statusLine)
    }



    /// Keep user-locked slots after try-another / regenerate (M1-F05-03 / AC-2).
    private static func reapplyLocks(
        _ outfit: StubOutfit,
        priorLocks: [StubOutfitAssignment],
        anchorId: UUID
    ) -> StubOutfit {
        var out = outfit
        for lock in priorLocks {
            guard let gid = lock.garmentId else { continue }
            if let idx = out.assignments.firstIndex(where: { $0.slot == lock.slot }) {
                out.assignments[idx].garmentId = gid
                out.assignments[idx].gapReason = nil
                out.assignments[idx].isLocked = true
                out.assignments[idx].isAnchor = false
            } else {
                out.assignments.append(
                    StubOutfitAssignment(slot: lock.slot, garmentId: gid, gapReason: nil, isAnchor: false, isLocked: true)
                )
            }
        }
        for i in out.assignments.indices {
            out.assignments[i].isAnchor = (out.assignments[i].garmentId == anchorId)
        }
        return out
    }

    /// Offline / unreachable fallback only — not the online path.
    private static func makeDemoOutfit(anchor: StubGarment, wardrobe: [StubGarment]) -> StubOutfit {
        func pick(_ slot: StubSlot, excluding: Set<UUID>) -> StubGarment? {
            wardrobe.first {
                $0.slot == slot && $0.isReady && $0.availability == "AVAILABLE" && !excluding.contains($0.id)
            }
        }

        var used: Set<UUID> = [anchor.id]
        var assignments: [StubOutfitAssignment] = [
            .init(slot: anchor.slot, garmentId: anchor.id, gapReason: nil, isAnchor: true)
        ]

        let order: [StubSlot] = [.outerwear, .jacket, .midLayer, .top, .bottom, .footwear, .accessory]
        for slot in order where slot != anchor.slot {
            if slot == .footwear {
                assignments.append(.init(
                    slot: .footwear,
                    garmentId: nil,
                    gapReason: "No footwear available today — laundry/packed items never fill a gap (D-25).",
                    isAnchor: false
                ))
                continue
            }
            if let g = pick(slot, excluding: used) {
                used.insert(g.id)
                assignments.append(.init(slot: slot, garmentId: g.id, gapReason: nil, isAnchor: false))
            }
        }

        return StubOutfit(
            id: UUID(),
            assignments: assignments,
            rationaleSummary: "Fixture stub outfit anchored on \(anchor.displayName). Not a live model result.",
            offlineCached: false
        )
    }
    func markContextChanged() {
        guard outfit != nil else { return }
        contextDirty = true
    }

    func updateOutfitForContext() async {
        clearWearFlash()
        // New occasion/weather session — previous exclusions were for the old context.
        resetShownOutfitExclusions()
        // Keep contextDirty until generate succeeds (#112 / D-38 — Cancel must restore “needs update”).
        await buildDemoOutfit(preserveLocks: true, intent: .updateContext)
    }

    private func readyOutfitGarmentIds() -> [UUID] {
        guard let outfit else { return [] }
        return outfit.assignments.compactMap(\.garmentId).filter { gid in
            garments.first(where: { $0.id == gid })?.isReady == true
        }
    }

    /// Persist intake lastWornOn, not the in-memory app overlay (#11 / #104).
    private func garmentForPersist(_ g: StubGarment) -> StubGarment {
        var copy = g
        copy.lastWornOn = fixtureLastWornOn[g.id]
        return copy
    }

    /// D-69 — delete one garment after the user confirms in the UI.
    func deleteGarment(id: UUID) async {
        invalidateInFlightEngineWork()
        do {
            try await store.deleteGarment(id: id)
            noteStoreDataGeneration()
            await refreshSessionFromStore()
            showToast(DataControlsCopy.deleteGarmentSuccess)
            recordDiagnostic("Garment deleted")
        } catch {
            noteStoreDataGeneration()
            await refreshSessionFromStore()
            showToast(DataControlsCopy.deleteGarmentFailure)
            recordDiagnostic("Couldn’t delete garment")
        }
    }

    /// D-70 — clear all garments and looks after the user confirms in the UI.
    func clearWardrobeAndLooks() async {
        invalidateInFlightEngineWork()
        do {
            try await store.clearWardrobeAndLooks()
            noteStoreDataGeneration()
            await refreshSessionFromStore()
            showToast(DataControlsCopy.clearWardrobeSuccess)
            recordDiagnostic("Wardrobe and looks cleared")
        } catch {
            noteStoreDataGeneration()
            await refreshSessionFromStore()
            showToast(DataControlsCopy.clearWardrobeFailure)
            recordDiagnostic("Couldn’t clear wardrobe")
        }
    }

    /// D-71 — replace the active profile with a blank unconfirmed draft after confirm.
    func resetActiveStyleProfile() async {
        invalidateInFlightEngineWork()
        do {
            let blank = try await store.resetActiveStyleProfile()
            noteStoreDataGeneration()
            await refreshSessionFromStore()
            styleProfile = blank
            showToast(DataControlsCopy.resetProfileSuccess)
            recordDiagnostic("Profile reset")
        } catch {
            noteStoreDataGeneration()
            await refreshSessionFromStore()
            if styleProfile == nil {
                await ensureEditableStyleProfile()
            }
            showToast(DataControlsCopy.resetProfileFailure)
            recordDiagnostic("Couldn’t reset profile")
        }
    }

    /// Open Profile with a blank unconfirmed draft when suppress left no row (never the bundled seed).
    func ensureEditableStyleProfile() async {
        if styleProfile != nil { return }
        if let existing = await store.fetchStyleProfile() {
            styleProfile = existing
            return
        }
        do {
            let blank = try await store.resetActiveStyleProfile()
            noteStoreDataGeneration()
            styleProfile = blank
        } catch {
            let blank = DestructiveCascade.blankUnconfirmedDraft(version: 1)
            styleProfile = blank
            try? await store.saveStyleProfile(blank)
        }
    }

    /// Cancel generate/swap and bump generation so late engine callbacks cannot persist.
    private func invalidateInFlightEngineWork() {
        cancelGeneration()
        activeGenerateGeneration += 1
        cancelSwapFlight()
    }

    private func cancelSwapFlight() {
        activeSwapGeneration += 1
        isLoadingAlternatives = false
    }

    private func noteStoreDataGeneration() {
        observedDataGeneration = store.dataGeneration
    }

    /// True when session still matches the last observed store generation (D-69/70/71 stale drop).
    func isCurrentStoreGeneration(_ capturedDataGeneration: Int? = nil) -> Bool {
        let expected = capturedDataGeneration ?? observedDataGeneration
        return expected == store.dataGeneration && observedDataGeneration == store.dataGeneration
    }

    /// Persist a look only if it was produced against the current store generation.
    @discardableResult
    func persistOutfitIfGenerationCurrent(
        _ outfit: StubOutfit,
        capturedDataGeneration: Int
    ) async -> Bool {
        guard isCurrentStoreGeneration(capturedDataGeneration) else { return false }
        do {
            try await store.saveOutfit(outfit)
            return true
        } catch {
            return false
        }
    }

    /// Test hook: late generate success after delete/clear/reset must no-op.
    var engineWorkGenerationForTests: UInt64 { activeGenerateGeneration }

    @discardableResult
    func applyLateEngineOutfitIfCurrent(
        _ outfit: StubOutfit,
        capturedEngineGeneration: UInt64,
        capturedDataGeneration: Int
    ) async -> Bool {
        guard capturedEngineGeneration == activeGenerateGeneration else { return false }
        guard await persistOutfitIfGenerationCurrent(
            outfit,
            capturedDataGeneration: capturedDataGeneration
        ) else { return false }
        self.outfit = outfit
        outfitWearable = true
        return true
    }

    private func refreshSessionFromStore() async {
        garments = await store.fetchGarments()
        sets = await store.fetchSets()
        let remainingIds = Set(garments.map(\.id))
        fixtureLastWornOn = fixtureLastWornOn.filter { remainingIds.contains($0.key) }
        if let fetched = await store.fetchStyleProfile() {
            styleProfile = fetched
        }
        await refreshWearState()
        reconcileSelectionAndOutfit(remainingIds: remainingIds)
    }

    private func reconcileSelectionAndOutfit(remainingIds: Set<UUID>) {
        if let selected = selectedGarment, !remainingIds.contains(selected.id) {
            selectedGarment = garments.first(where: { $0.isReady && $0.availability == "AVAILABLE" })
                ?? garments.first
        }
        if garments.isEmpty {
            selectedGarment = nil
        }
        let outfitIds = outfit.map { Set(Self.garmentIds(of: $0)) } ?? []
        let outfitMissingPieces = !outfitIds.isSubset(of: remainingIds)
        if remainingIds.isEmpty || outfitMissingPieces {
            clearBoardAndSwapState()
        }
    }

    private func clearBoardAndSwapState() {
        outfit = nil
        outfitWearable = false
        outfitSnapshotBeforeGenerate = nil
        wearableSnapshotBeforeGenerate = false
        swapAlternatives = []
        swapEmptyReason = nil
        swapSlot = nil
        swapSheetDetail = nil
        swapUndoAssignmentsSnapshot = nil
        contextDirty = false
        generateFailureMessage = nil
        generateFailureSubtitle = nil
        generateFailureDetail = nil
        noAlternativeReason = nil
        resetShownOutfitExclusions()
        clearWearFlash()
    }

    private func refreshWearState() async {
        let events = await store.fetchWearEvents()
        wearEvents = events
        let aggregates = await store.fetchWearAggregates()
        wearCounts = aggregates.counts
        lastWornFromApp = aggregates.lastWorn
        applyLastWornOverlay()
    }

    private func applyLastWornOverlay() {
        var next = garments
        for i in next.indices {
            let id = next[i].id
            if let appDay = lastWornFromApp[id] {
                next[i].lastWornOn = WearLogging.isoDay(from: appDay)
            } else {
                next[i].lastWornOn = fixtureLastWornOn[id]
            }
            if selectedGarment?.id == id {
                selectedGarment = next[i]
            }
        }
        garments = next
    }

}

// Mutation stays beside the private setters; cross-file feedback calls these methods.
extension LoopDemoModel {
    func updateToastState(_ message: String?, undoAvailable: Bool = false) {
        activeToast = message
        toastUndoAvailable = undoAvailable
    }

    /// D-75 — persist / store seam for `LoopDemoModel+DailyWear`. Fail closed.
    func persistDailyWearEvent(_ event: StubWearEvent) async throws {
        try await store.saveWearEvent(event)
    }

    func fetchAllWearEventsForDailyWear() async -> [StubWearEvent] {
        await store.fetchWearEvents()
    }

    func reloadDailyWearState() async {
        await refreshWearState()
    }

    func suggestedReadyOutfitGarmentIds() -> [UUID] {
        readyOutfitGarmentIds()
    }

    func setLastWornOutfitIdForDailyWear(_ id: UUID?) {
        lastWornOutfitId = id
    }

    func beginDailyWearWrite() -> Bool {
        if dailyWearWriteInFlight { return false }
        dailyWearWriteInFlight = true
        return true
    }

    func endDailyWearWrite() {
        dailyWearWriteInFlight = false
    }

    func observedDataGenerationForDailyWear() -> Int {
        observedDataGeneration
    }

    func recordDiagnostic(_ message: String) {
#if DEBUG
        diagnosticLog.append(message)
        if diagnosticLog.count > 80 {
            diagnosticLog.removeFirst(diagnosticLog.count - 80)
        }
#endif
    }

    private func elapsedMilliseconds(since start: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(start) * 1000))
    }

    private func recordGenerationLatency(milliseconds: Int, outcome: String) {
        let note = OutfitEngineClient.GenerationLatencyBudget.note(milliseconds: milliseconds)
        generationLatencySamples.append(
            OutfitEngineClient.GenerationLatencySample(
                milliseconds: milliseconds,
                outcome: outcome,
                note: note
            )
        )
        if generationLatencySamples.count > 40 {
            generationLatencySamples.removeFirst(generationLatencySamples.count - 40)
        }
        recordDiagnostic("Generate \(outcome) in \(milliseconds) ms (\(note))")
    }

#if DEBUG
    func clearDiagnosticLog() {
        diagnosticLog.removeAll()
    }
#endif
}

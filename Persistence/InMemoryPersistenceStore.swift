import Foundation

/// Placeholder store for M0/M1 thin shell. Seeded from fixture wardrobe JSON.
final class InMemoryPersistenceStore: PersistenceStore, @unchecked Sendable {
    static let shared = InMemoryPersistenceStore()

    var backendName: String { "in-memory + fixtures" }

    private struct MemoryCameraPending {
        var id: UUID
        var masterURI: String
        var reviewState: String
        var garmentId: UUID?
    }

    private var garments: [StubGarment]
    private var outfits: [StubOutfit] = []
    private var wears: [StubWearEvent] = []
    private var profiles: [StubStyleProfile] = []
    private var sets: [StubSet]
    private var cameraPendings: [UUID: MemoryCameraPending] = [:]
    private var wearingPhotos: [StubWearingPhoto] = []
    let wearingPhotoFiles: WearingPhotoFileStore
    private let defaults: UserDefaults
    private let lock = NSLock()
    private var generation = 0

    var dataGeneration: Int {
        lock.lock()
        defer { lock.unlock() }
        return generation
    }

    init(
        garments: [StubGarment]? = nil,
        sets: [StubSet]? = nil,
        defaults: UserDefaults = .standard,
        wearingPhotoFiles: WearingPhotoFileStore = .temporary()
    ) {
        if let garments {
            self.garments = garments
            self.sets = sets ?? []
        } else {
            self.garments = FixtureWardrobeLoader.loadGarments()
            self.sets = sets ?? FixtureWardrobeLoader.loadSets()
        }
        self.defaults = defaults
        self.wearingPhotoFiles = wearingPhotoFiles
    }

    func fetchGarments() async -> [StubGarment] {
        lock.lock(); defer { lock.unlock() }
        return garments
    }

    func saveGarment(_ garment: StubGarment) async throws {
        lock.lock(); defer { lock.unlock() }
        var stored = garment
        stored.purchasePrice = StubGarment.persistedPurchasePrice(garment.purchasePrice)
        if stored.purchasePrice == nil {
            stored.purchaseCurrency = nil
        }
        if let idx = garments.firstIndex(where: { $0.id == stored.id }) {
            garments[idx] = stored
        } else {
            garments.append(stored)
        }
    }

    func fetchOutfits() async -> [StubOutfit] {
        lock.lock(); defer { lock.unlock() }
        return outfits
    }

    func saveOutfit(_ outfit: StubOutfit) async throws {
        lock.lock(); defer { lock.unlock() }
        if let idx = outfits.firstIndex(where: { $0.id == outfit.id }) {
            var updated = outfit
            // #44: mirror SwiftData — a stub without metadata keeps the stored metadata.
            if updated.generation == nil {
                updated.generation = outfits[idx].generation
            }
            outfits[idx] = updated
        } else {
            outfits.append(outfit)
        }
    }

    func fetchWearEvents() async -> [StubWearEvent] {
        lock.lock(); defer { lock.unlock() }
        return wears
    }

    func fetchWearEvents(on day: Date) async -> [StubWearEvent] {
        lock.lock(); defer { lock.unlock() }
        return wears.filter { Calendar.current.isDate($0.wornOn, inSameDayAs: day) }
    }

    func fetchWearAggregates() async -> WearAggregates {
        lock.lock(); defer { lock.unlock() }
        return WearAggregates(
            counts: WearLogging.counts(from: wears),
            lastWorn: WearLogging.lastWornOnByGarment(events: wears)
        )
    }

    func saveWearEvent(_ event: StubWearEvent) async throws {
        lock.lock(); defer { lock.unlock() }
        if let idx = wears.firstIndex(where: { $0.id == event.id }) {
            wears[idx] = event
        } else {
            wears.append(event)
        }
    }

    func voidWearEvent(id: UUID) async throws {
        lock.lock(); defer { lock.unlock() }
        guard let idx = wears.firstIndex(where: { $0.id == id }) else { return }
        guard wears[idx].voidedAt == nil else { return }
        wears[idx].voidedAt = Date()
    }

    func fetchStyleProfile() async -> StubStyleProfile? {
        lock.lock(); defer { lock.unlock() }
        return profiles.max(by: { $0.version < $1.version })
    }

    func saveStyleProfile(_ profile: StubStyleProfile) async throws {
        lock.lock(); defer { lock.unlock() }
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
        } else {
            profiles.append(profile)
        }
    }

    func fetchSets() async -> [StubSet] {
        lock.lock(); defer { lock.unlock() }
        return sets
    }

    func fetchAllStyleProfiles() async -> [StubStyleProfile] {
        lock.lock(); defer { lock.unlock() }
        return profiles.sorted { $0.version > $1.version }
    }

    func deleteGarment(id: UUID) async throws {
        var cleanupPaths: [String] = []
        var referencedByOthers = Set<String>()
        var didDelete = false
        var galleryFiles: [UUID] = []
        lock.lock()
        if let garment = garments.first(where: { $0.id == id }) {
            didDelete = true
            galleryFiles = Self.fileIds(of: wearingPhotos.filter { $0.garmentId == id })
            wearingPhotos.removeAll { $0.garmentId == id }
            if let path = garment.imagePath { cleanupPaths.append(path) }
            referencedByOthers = Set(garments.compactMap { other in
                other.id == id ? nil : other.imagePath
            })
            outfits = DestructiveCascade.outfitsRemovingGarment(id, from: outfits)
            wears = DestructiveCascade.wearsRemovingGarment(id, from: wears)
            let rewrite = DestructiveCascade.setsRemovingGarment(id, from: sets)
            sets = rewrite.kept
            garments = garments.filter { $0.id != id }
            garments = DestructiveCascade.garmentsClearingDeletedSets(
                garments,
                deletedSetIds: rewrite.deletedIds
            )
        }
        let wardrobeEmpty = garments.isEmpty
        generation += 1
        lock.unlock()
        if wardrobeEmpty {
            SeedSuppression.suppressAutomaticWardrobeSeed(in: defaults)
        }
        if didDelete {
            UserGarmentPhotoStore.deleteOwnedFiles(
                for: id,
                additionalPaths: cleanupPaths,
                excluding: referencedByOthers
            )
        }
        wearingPhotoFiles.remove(galleryFiles)
    }

    func clearWardrobeAndLooks() async throws {
        var cleanup: [(UUID, String?)] = []
        var pendingCleanup: [(UUID, String)] = []
        var galleryFiles: [UUID] = []
        lock.lock()
        galleryFiles = Self.fileIds(of: wearingPhotos)
        wearingPhotos = []
        cleanup = garments.map { ($0.id, $0.imagePath) }
        pendingCleanup = cameraPendings.values.map { ($0.id, $0.masterURI) }
        cameraPendings = [:]
        garments = []
        outfits = []
        wears = []
        sets = []
        generation += 1
        lock.unlock()
        SeedSuppression.suppressAutomaticWardrobeSeed(in: defaults)
        for (id, path) in cleanup {
            UserGarmentPhotoStore.deleteOwnedFiles(
                for: id,
                additionalPaths: path.map { [$0] } ?? []
            )
        }
        for (id, path) in pendingCleanup {
            UserGarmentPhotoStore.removeFile(imagePath: path)
            UserGarmentPhotoStore.removeFiles(forGarmentId: id)
        }
        wearingPhotoFiles.remove(galleryFiles)
    }

    func resetActiveStyleProfile() async throws -> StubStyleProfile {
        var pendingCleanup: [(UUID, String)] = []
        let profile: StubStyleProfile
        lock.lock()
        pendingCleanup = cameraPendings.values
            .filter { $0.reviewState == "PENDING" && $0.garmentId == nil }
            .map { ($0.id, $0.masterURI) }
        for item in pendingCleanup {
            cameraPendings.removeValue(forKey: item.0)
        }
        if let current = profiles.max(by: { $0.version < $1.version }),
           DestructiveCascade.isBlankUnconfirmedDraft(current) {
            generation += 1
            SeedSuppression.suppressAutomaticProfileSeed(in: defaults)
            profile = current
        } else {
            let nextVersion = (profiles.map(\.version).max() ?? 0) + 1
            let blank = DestructiveCascade.blankUnconfirmedDraft(version: nextVersion)
            profiles.append(blank)
            generation += 1
            SeedSuppression.suppressAutomaticProfileSeed(in: defaults)
            profile = blank
        }
        lock.unlock()
        for (id, path) in pendingCleanup {
            UserGarmentPhotoStore.removeFile(imagePath: path)
            UserGarmentPhotoStore.removeFiles(forGarmentId: id)
        }
        return profile
    }

    func beginCameraPending(jpegData: Data) async throws -> UUID {
        await CameraPersistHooks.awaitInjectedDelay()
        let id = UUID()
        let path: String
        do {
            path = try UserGarmentPhotoStore.persistPendingJPEG(from: jpegData, captureId: id)
        } catch {
            throw CameraPersistError.map(error)
        }
        CameraPersistHooks.lastPendingFilePath = path
        do {
            if let injected = CameraPersistHooks.failAfterPendingFileWrite {
                CameraPersistHooks.failAfterPendingFileWrite = nil
                throw injected
            }
            lock.lock()
            cameraPendings[id] = MemoryCameraPending(
                id: id,
                masterURI: path,
                reviewState: "PENDING",
                garmentId: nil
            )
            lock.unlock()
            return id
        } catch {
            UserGarmentPhotoStore.removeFile(imagePath: path)
            UserGarmentPhotoStore.removeFiles(forGarmentId: id)
            throw CameraPersistError.map(error)
        }
    }

    func abandonCameraPending(id: UUID) async throws {
        var paths: [String] = []
        var shouldDeleteFiles = true
        lock.lock()
        if let pending = cameraPendings[id] {
            if pending.reviewState == "COMMITTED" || pending.garmentId != nil {
                shouldDeleteFiles = false
            } else {
                paths.append(pending.masterURI)
                cameraPendings.removeValue(forKey: id)
            }
        } else if garments.contains(where: { $0.id == id }) {
            shouldDeleteFiles = false
        } else {
            paths.append(UserGarmentPhotoStore.pendingPhotoPath(for: id))
        }
        lock.unlock()
        guard shouldDeleteFiles else { return }
        for path in paths {
            UserGarmentPhotoStore.removeFile(imagePath: path)
        }
        UserGarmentPhotoStore.removeFiles(forGarmentId: id)
    }

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
        guard let slot else { throw CameraPersistError.slotRequired }
        lock.lock()
        defer { lock.unlock() }
        guard let pending = cameraPendings[id],
              pending.reviewState == "PENDING",
              pending.garmentId == nil,
              !garments.contains(where: { $0.id == id })
        else {
            throw CameraPersistError.pendingUnavailable
        }
        let userPath = UserGarmentPhotoStore.userPhotoPath(for: id)
        guard UserGarmentPhotoStore.resolvedFileURL(pending.masterURI) != nil
                || UserGarmentPhotoStore.resolvedFileURL(userPath) != nil
        else {
            throw CameraPersistError.saveFailed
        }
        let garment = CameraPendingCommitBuilder.garment(
            id: id,
            slot: slot,
            name: name,
            imagePath: userPath,
            color: color,
            pattern: pattern,
            surface: surface,
            formality: formality,
            warmth: warmth
        )
        cameraPendings.removeValue(forKey: id)
        garments.append(garment)
        return garment
    }

    func stagePhotoReplace(garmentId: UUID, jpegData: Data) async throws -> UUID {
        await PhotoReplacePersistHooks.awaitInjectedDelay()
        lock.lock()
        let exists = garments.contains { $0.id == garmentId }
        lock.unlock()
        guard exists else { throw PhotoReplacePersistError.garmentUnavailable }

        let stagingId = UUID()
        let path: String
        do {
            path = try UserGarmentPhotoStore.persistReplaceJPEG(from: jpegData, stagingId: stagingId)
        } catch {
            throw PhotoReplacePersistError.map(error)
        }
        PhotoReplacePersistHooks.lastStagedPath = path
        if let injected = PhotoReplacePersistHooks.failAfterStagingFileWrite {
            PhotoReplacePersistHooks.failAfterStagingFileWrite = nil
            UserGarmentPhotoStore.removeFile(imagePath: path)
            UserGarmentPhotoStore.removeFiles(forGarmentId: stagingId)
            throw PhotoReplacePersistError.map(injected)
        }
        return stagingId
    }

    func abandonPhotoReplace(stagingId: UUID) async throws {
        try await PhotoReplaceGate.shared.run {
            self.abandonPhotoReplaceUnlocked(stagingId: stagingId)
        }
    }

    func replaceGarmentPhoto(garmentId: UUID, stagingId: UUID) async throws -> StubGarment {
        try await PhotoReplaceGate.shared.run {
            try await self.replaceGarmentPhotoUnlocked(garmentId: garmentId, stagingId: stagingId)
        }
    }

    private func abandonPhotoReplaceUnlocked(stagingId: UUID) {
        let replacePath = UserGarmentPhotoStore.replacePhotoPath(for: stagingId)
        let userPath = UserGarmentPhotoStore.userPhotoPath(for: stagingId)
        lock.lock()
        let referenced = garments.contains {
            $0.imagePath == replacePath || $0.imagePath == userPath
        }
        lock.unlock()
        guard !referenced else { return }
        UserGarmentPhotoStore.removeFile(imagePath: replacePath)
        UserGarmentPhotoStore.removeFiles(forGarmentId: stagingId)
    }

    private func replaceGarmentPhotoUnlocked(garmentId: UUID, stagingId: UUID) async throws -> StubGarment {
        await PhotoReplacePersistHooks.awaitInjectedDelay()
        let stagedPath = UserGarmentPhotoStore.replacePhotoPath(for: stagingId)
        let newPath = UserGarmentPhotoStore.userPhotoPath(for: stagingId)
        guard UserGarmentPhotoStore.resolvedFileURL(stagedPath) != nil
                || UserGarmentPhotoStore.resolvedFileURL(newPath) != nil
        else {
            throw PhotoReplacePersistError.saveFailed
        }
        if let injected = PhotoReplacePersistHooks.failBeforeMetadataCommit {
            PhotoReplacePersistHooks.failBeforeMetadataCommit = nil
            abandonPhotoReplaceUnlocked(stagingId: stagingId)
            throw PhotoReplacePersistError.map(injected)
        }

        var oldPaths: [String] = []
        var referencedByOthers = Set<String>()
        let updated: StubGarment
        lock.lock()
        guard let idx = garments.firstIndex(where: { $0.id == garmentId }) else {
            lock.unlock()
            abandonPhotoReplaceUnlocked(stagingId: stagingId)
            throw PhotoReplacePersistError.garmentUnavailable
        }
        if garments[idx].imagePath == newPath {
            updated = garments[idx]
            lock.unlock()
            return updated
        }
        if let path = garments[idx].imagePath { oldPaths.append(path) }
        referencedByOthers = Set(garments.compactMap { other in
            other.id == garmentId ? nil : other.imagePath
        })
        referencedByOthers.insert(newPath)
        referencedByOthers.insert(stagedPath)
        garments[idx].imagePath = newPath
        updated = garments[idx]
        lock.unlock()

        UserGarmentPhotoStore.deleteOwnedFiles(
            for: garmentId,
            additionalPaths: oldPaths,
            excluding: referencedByOthers
        )
        UserGarmentPhotoStore.evictThumbnails()
        return updated
    }
}

// MARK: - Sprint 9 wearing gallery (mirrors SwiftDataPersistenceStore+WearingPhotos)

extension InMemoryPersistenceStore {
    fileprivate static func fileIds(of photos: [StubWearingPhoto]) -> [UUID] {
        photos.flatMap { [$0.displayFileId] + ($0.sourceFileId.map { [$0] } ?? []) }
    }

    func fetchWearingPhotos(garmentId: UUID) async -> [StubWearingPhoto] {
        lock.lock(); defer { lock.unlock() }
        return WearingPhotoOrdering.sorted(wearingPhotos.filter { $0.garmentId == garmentId })
    }

    func addWearingPhoto(_ request: WearingPhotoAddRequest) async throws -> StubWearingPhoto {
        try await PhotoReplaceGate.wearingPhotos.run {
            try self.addWearingPhotoUnlocked(request)
        }
    }

    func updateWearingPhotoDisplay(id: UUID, displayJPEG: Data) async throws -> StubWearingPhoto {
        try await PhotoReplaceGate.wearingPhotos.run {
            try self.updateWearingPhotoDisplayUnlocked(id: id, displayJPEG: displayJPEG)
        }
    }

    func removeWearingPhoto(id: UUID) async throws {
        try await PhotoReplaceGate.wearingPhotos.run {
            self.removeWearingPhotoUnlocked(id: id)
        }
    }

    func setWearingPhotoExportState(id: UUID, state: WearingPhotoExportState) async throws -> StubWearingPhoto {
        lock.lock(); defer { lock.unlock() }
        guard let idx = wearingPhotos.firstIndex(where: { $0.id == id }) else {
            throw WearingPhotoPersistError.photoUnavailable
        }
        wearingPhotos[idx].exportState = state
        return wearingPhotos[idx]
    }

    func sweepOrphanWearingPhotoFiles() async {
        lock.lock()
        let referenced = Set(Self.fileIds(of: wearingPhotos))
        lock.unlock()
        wearingPhotoFiles.sweepOrphans(referenced: referenced)
    }

    private func addWearingPhotoUnlocked(_ request: WearingPhotoAddRequest) throws -> StubWearingPhoto {
        lock.lock()
        let existing = wearingPhotos.first { $0.id == request.id }
        lock.unlock()
        if let existing { return existing }

        let displayId = try wearingPhotoFiles.write(request.displayJPEG)
        var sourceId: UUID?
        if let source = request.sourceJPEG {
            do {
                sourceId = try wearingPhotoFiles.write(source)
            } catch {
                wearingPhotoFiles.remove([displayId])
                throw WearingPhotoPersistError.map(error)
            }
        }
        let newFiles = [displayId] + (sourceId.map { [$0] } ?? [])
        if let injected = WearingPhotoPersistHooks.failBeforeMetadataCommit {
            WearingPhotoPersistHooks.failBeforeMetadataCommit = nil
            wearingPhotoFiles.remove(newFiles)
            throw WearingPhotoPersistError.map(injected)
        }

        lock.lock()
        guard garments.contains(where: { $0.id == request.garmentId }) else {
            lock.unlock()
            wearingPhotoFiles.remove(newFiles)
            throw WearingPhotoPersistError.garmentUnavailable
        }
        let photo = StubWearingPhoto(
            id: request.id,
            garmentId: request.garmentId,
            displayFileId: displayId,
            sourceFileId: sourceId,
            addedAt: request.addedAt,
            updatedAt: request.addedAt,
            source: request.source,
            exportState: nil
        )
        wearingPhotos.append(photo)
        lock.unlock()
        return photo
    }

    private func updateWearingPhotoDisplayUnlocked(id: UUID, displayJPEG: Data) throws -> StubWearingPhoto {
        let newDisplayId = try wearingPhotoFiles.write(displayJPEG)
        if let injected = WearingPhotoPersistHooks.failBeforeMetadataCommit {
            WearingPhotoPersistHooks.failBeforeMetadataCommit = nil
            wearingPhotoFiles.remove([newDisplayId])
            throw WearingPhotoPersistError.map(injected)
        }
        lock.lock()
        guard let idx = wearingPhotos.firstIndex(where: { $0.id == id }) else {
            lock.unlock()
            wearingPhotoFiles.remove([newDisplayId])
            throw WearingPhotoPersistError.photoUnavailable
        }
        guard garments.contains(where: { $0.id == wearingPhotos[idx].garmentId }) else {
            lock.unlock()
            wearingPhotoFiles.remove([newDisplayId])
            throw WearingPhotoPersistError.garmentUnavailable
        }
        let previous = wearingPhotos[idx].displayFileId
        wearingPhotos[idx].displayFileId = newDisplayId
        if wearingPhotos[idx].sourceFileId == nil {
            wearingPhotos[idx].sourceFileId = previous
        }
        wearingPhotos[idx].updatedAt = Date()
        let updated = wearingPhotos[idx]
        lock.unlock()
        if updated.sourceFileId != previous {
            wearingPhotoFiles.remove([previous])
        }
        return updated
    }

    private func removeWearingPhotoUnlocked(id: UUID) {
        lock.lock()
        let removed = wearingPhotos.filter { $0.id == id }
        wearingPhotos.removeAll { $0.id == id }
        lock.unlock()
        wearingPhotoFiles.remove(Self.fileIds(of: removed))
    }
}

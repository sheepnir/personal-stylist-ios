import Foundation

enum DailyWearMode: Equatable {
    case newWear
    case correction
}

enum DailyWearCompletion: Equatable {
    /// Persist succeeded, or same-day repeat is already logged — leave the picker/success stack.
    case popToWardrobe
    /// Empty/blocked/failed/in-flight — stay put; no success chrome.
    case remain
}

/// Board primary wear control. Logged-today is explicit correction — never a silent replace.
enum DailyWearBoardPrimary: Equatable {
    case wearingThis
    case changeWhatIWore

    var title: String {
        switch self {
        case .wearingThis: return DailyWearCopy.wearingThis
        case .changeWhatIWore: return DailyWearCopy.changeWhatIWore
        }
    }

    var persistsFromBoard: Bool { self == .wearingThis }

    var accessibilityHint: String {
        switch self {
        case .wearingThis: return DailyWearCopy.submitHintNew
        case .changeWhatIWore: return DailyWearCopy.submitHintCorrection
        }
    }

    static func resolve(hasLoggedToday: Bool) -> DailyWearBoardPrimary {
        hasLoggedToday ? .changeWhatIWore : .wearingThis
    }
}

struct DailyWearPickerSection: Identifiable, Equatable {
    var id: String
    var title: String
    var garments: [StubGarment]
    var isUnavailableGroup: Bool
}

struct DailyWearTodaySnapshot: Equatable {
    var event: StubWearEvent
    var garments: [StubGarment]
    var leadName: String
    var extraCount: Int
}

extension LoopDemoModel {
    func loggedTodayEvent(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> StubWearEvent? {
        WearLogging.loggedToday(events: wearEvents, now: now, calendar: calendar)
    }

    var hasLoggedToday: Bool { loggedTodayEvent() != nil }

    var dailyWearMode: DailyWearMode {
        hasLoggedToday ? .correction : .newWear
    }

    var showsLoggedTodayRow: Bool { hasLoggedToday }

    var showsReturnToOutfitBanner: Bool {
        !hasLoggedToday && outfit != nil
    }

    var showsReplacingUnloggedSessionNote: Bool {
        guard let event = loggedTodayEvent(), outfit != nil else { return false }
        return Set(suggestedReadyOutfitGarmentIds()) != Set(event.garmentIds)
    }

    var dailyWearShowsSuccessChrome: Bool { hasLoggedToday }

    var dailyWearShowsPersistFailure: Bool {
        wearConfirmedMessage == DailyWearCopy.persistFailed
    }

    var boardWearPrimary: DailyWearBoardPrimary {
        DailyWearBoardPrimary.resolve(hasLoggedToday: hasLoggedToday)
    }

    func loggedTodaySnapshot(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DailyWearTodaySnapshot? {
        guard let event = loggedTodayEvent(now: now, calendar: calendar) else { return nil }
        let worn = wornGarments(for: event.garmentIds)
        return DailyWearTodaySnapshot(
            event: event,
            garments: worn,
            leadName: DailyWearCopy.leadName(worn),
            extraCount: DailyWearCopy.extraCount(total: worn.count)
        )
    }

    func wornGarmentsForDailyWearDisplay() -> [StubGarment] {
        if let snapshot = loggedTodaySnapshot() {
            return snapshot.garments
        }
        return wornGarments(for: suggestedReadyOutfitGarmentIds())
    }

    /// READY pieces still present. Unavailable items are listed, not preselected.
    func isEligibleForDailyWear(_ garment: StubGarment) -> Bool {
        garment.isReady
    }

    func isPreselectEligibleForDailyWear(_ garment: StubGarment) -> Bool {
        garment.isReady && garment.availabilityToken == .available
    }

    func dailyWearPreselectedIds(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Set<UUID> {
        let suggested: [UUID]
        if let event = loggedTodayEvent(now: now, calendar: calendar) {
            suggested = event.garmentIds
        } else {
            suggested = suggestedReadyOutfitGarmentIds()
        }
        return Set(suggested.filter { id in
            guard let garment = garments.first(where: { $0.id == id }) else { return false }
            return isPreselectEligibleForDailyWear(garment)
        })
    }

    func dailyWearPickerSections(search: String) -> [DailyWearPickerSection] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let ready = visibleGarments.filter { isEligibleForDailyWear($0) }
        let matched = ready.filter { DailyWearCopy.matchesSearch($0, query: query) }
        let available = matched
            .filter { $0.availabilityToken == .available }
            .sorted { $0.slot.wearingOrderIndex < $1.slot.wearingOrderIndex }
        let unavailable = matched
            .filter { $0.availabilityToken != .available }
            .sorted { $0.slot.wearingOrderIndex < $1.slot.wearingOrderIndex }

        var sections: [DailyWearPickerSection] = []
        for slot in StubSlot.wearingOrder {
            let group = available.filter { $0.slot == slot }
            guard !group.isEmpty else { continue }
            sections.append(
                DailyWearPickerSection(
                    id: slot.rawValue,
                    title: slot.displayLabel,
                    garments: group,
                    isUnavailableGroup: false
                )
            )
        }
        if !unavailable.isEmpty {
            sections.append(
                DailyWearPickerSection(
                    id: "unavailable",
                    title: DailyWearCopy.notAvailableToday,
                    garments: unavailable,
                    isUnavailableGroup: true
                )
            )
        }
        return sections
    }

    /// Fail-closed daily wear write. Distinguishes new wear vs correction in the UI only;
    /// persistence still uses `WearLogging.confirm` (void same-day, then insert).
    @discardableResult
    func submitDailyWear(
        garmentIds: [UUID]? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async -> DailyWearCompletion {
        guard beginDailyWearWrite() else { return .remain }
        defer { endDailyWearWrite() }

        let existing = await fetchAllWearEventsForDailyWear()
        if garmentIds == nil,
           WearLogging.loggedToday(events: existing, now: now, calendar: calendar) != nil {
            wearConfirmedMessage = DailyWearCopy.useCorrectionInstead
            recordDiagnostic("Wear blocked — already logged today")
            return .remain
        }

        let allowed = Set(garments.filter(isEligibleForDailyWear).map(\.id))
        let ids: [UUID]
        let sourceOutfitId: UUID?
        if let garmentIds {
            ids = garmentIds.filter { allowed.contains($0) }
            sourceOutfitId = nil
        } else {
            ids = suggestedReadyOutfitGarmentIds().filter { allowed.contains($0) }
            sourceOutfitId = outfit?.id
        }
        guard !ids.isEmpty else {
            wearConfirmedMessage = DailyWearCopy.blockedDrafts
            recordDiagnostic("Wear blocked (draft)")
            return .remain
        }

        let originals = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let result = WearLogging.confirm(
            existing: existing,
            garmentIds: ids,
            wornOn: now,
            sourceOutfitId: sourceOutfitId,
            calendar: calendar
        )

        if !result.didWrite {
            await reloadDailyWearState()
            wearConfirmedMessage = DailyWearCopy.alreadyLogged
            recordDiagnostic(result.statusLine)
            return .popToWardrobe
        }

        var persistedVoids: [StubWearEvent] = []
        do {
            for voided in result.voided {
                try await persistDailyWearEvent(voided)
                persistedVoids.append(voided)
            }
            if let event = result.event {
                try await persistDailyWearEvent(event)
                setLastWornOutfitIdForDailyWear(event.sourceOutfitId ?? outfit?.id)
            }
        } catch {
            for voided in persistedVoids {
                if let original = originals[voided.id] {
                    try? await persistDailyWearEvent(original)
                }
            }
            await reloadDailyWearState()
            wearConfirmedMessage = DailyWearCopy.persistFailed
            recordDiagnostic("Wear persist failed")
            return .remain
        }

        if let outfit {
            _ = await persistOutfitIfGenerationCurrent(
                outfit,
                capturedDataGeneration: observedDataGenerationForDailyWear()
            )
        }
        await reloadDailyWearState()
        guard loggedTodayEvent(now: now, calendar: calendar) != nil else {
            wearConfirmedMessage = DailyWearCopy.persistFailed
            recordDiagnostic("Wear persist failed")
            return .remain
        }

        let mode: DailyWearMode = result.voided.isEmpty ? .newWear : .correction
        wearConfirmedMessage = mode == .correction
            ? DailyWearCopy.updatedTodayToast
            : DailyWearCopy.loggedCount(ids.count)
        wearFlashToken = UUID()
        recordDiagnostic(result.statusLine)
        if sourceOutfitId != nil {
            notifyWearLoggedForToday()
        }
        showToast(mode == .correction ? DailyWearCopy.updatedTodayToast : DailyWearCopy.loggedTodayToast)
        return .popToWardrobe
    }

    @discardableResult
    func undoDailyWear(
        now: Date = Date(),
        calendar: Calendar = .current
    ) async -> Bool {
        guard beginDailyWearWrite() else { return false }
        defer { endDailyWearWrite() }

        let existing = await fetchAllWearEventsForDailyWear()
        guard let result = WearLogging.undoToday(events: existing, now: now, calendar: calendar) else {
            wearConfirmedMessage = "Nothing to undo"
            recordDiagnostic("Nothing to undo")
            return false
        }
        do {
            for ev in result.updated {
                try await persistDailyWearEvent(ev)
            }
        } catch {
            await reloadDailyWearState()
            wearConfirmedMessage = DailyWearCopy.persistFailed
            recordDiagnostic("Wear persist failed")
            return false
        }
        setLastWornOutfitIdForDailyWear(nil)
        await reloadDailyWearState()
        wearConfirmedMessage = result.message
        wearFlashToken = nil
        recordDiagnostic(result.statusLine)
        return true
    }

    func cancelDailyWearCorrection() {
        // Cancel writes nothing. Chrome stays on the prior persisted event.
        recordDiagnostic("Daily wear correction cancelled")
    }

    /// Board `confirmWear` used `try?` and still set a success line. Success chrome
    /// is derived from persisted non-voided today-wear only.
    func reconcileDailyWearSuccessChrome(
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        if loggedTodayEvent(now: now, calendar: calendar) != nil { return }
        guard let message = wearConfirmedMessage else { return }
        let claimedSuccess = message.hasPrefix("Logged ")
            || message == DailyWearCopy.loggedTodayToast
            || message == DailyWearCopy.updatedTodayToast
            || message == DailyWearCopy.alreadyLogged
        if claimedSuccess {
            wearConfirmedMessage = DailyWearCopy.persistFailed
        }
    }

    private func wornGarments(for ids: [UUID]) -> [StubGarment] {
        ids.compactMap { id in
            garments.first(where: { $0.id == id && $0.isReady })
        }
        .sorted { $0.slot.wearingOrderIndex < $1.slot.wearingOrderIndex }
    }
}

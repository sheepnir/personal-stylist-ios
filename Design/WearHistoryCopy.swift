import Foundation

/// D-72 / #120 wear-history copy — never raw enums, HTTP, or persistence tokens.
enum WearHistoryCopy {
    static let sectionTitle = "Wear history"
    static let seeAll = "See all"
    static let empty = "No wears logged yet"
    static let voidedLabel = "Voided"
    static let voidAction = "Void this wear"
    static let voidTitle = "Void this wear?"
    static let voidConfirm = "Void wear"
    static let cancel = "Cancel"
    static let voidMessage =
        "This removes the wear from counts and cost per wear. The record stays marked voided. This cannot be undone."

    static let editAction = "Edit"
    static let editAccessibility = "Edit garment details"
    static let editHint = "Opens name, slot, and readiness fields"
    static let seeAllAccessibility = "See all wears"
    static let seeAllHint = "Shows every logged wear, including voided ones"
    static let voidHint = "Removes this wear from counts after confirmation"
    static let profileUnlockFootnote = "Confirm your style profile to unlock outfit builds."
    static let profileUnlockAccessibility = "Confirm your style profile to unlock outfit builds"
    static let profileUnlockHint = "Opens your style profile"

    static func formattedDate(_ date: Date, locale: Locale = .current, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    static func datedWearLine(wornOn: Date, locale: Locale = .current, calendar: Calendar = .current) -> String {
        "Worn \(formattedDate(wornOn, locale: locale, calendar: calendar))"
    }

    /// Date + look name when known; otherwise a dated wear line.
    static func rowLine(
        wornOn: Date,
        outfitName: String?,
        locale: Locale = .current,
        calendar: Calendar = .current
    ) -> String {
        let date = formattedDate(wornOn, locale: locale, calendar: calendar)
        if let outfitName {
            let trimmed = outfitName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return "\(date) · \(trimmed)"
            }
        }
        return datedWearLine(wornOn: wornOn, locale: locale, calendar: calendar)
    }

    static func rowAccessibility(
        wornOn: Date,
        outfitName: String?,
        isVoided: Bool,
        locale: Locale = .current,
        calendar: Calendar = .current
    ) -> String {
        var parts = [rowLine(wornOn: wornOn, outfitName: outfitName, locale: locale, calendar: calendar)]
        if isVoided {
            parts.append(voidedLabel)
        }
        return parts.joined(separator: ". ")
    }

    /// `LoopDemoModel` has no saved-looks catalog. A `sourceOutfitId` is “known”
    /// when it matches the in-session board outfit; otherwise name the look from
    /// the garments on the wear event.
    static func resolvedOutfitName(
        sourceOutfitId: UUID?,
        currentOutfit: StubOutfit?,
        wornGarmentIds: [UUID],
        garments: [StubGarment]
    ) -> String? {
        guard sourceOutfitId != nil else { return nil }
        let ids: [UUID]
        if let currentOutfit, currentOutfit.id == sourceOutfitId {
            ids = currentOutfit.assignments.compactMap(\.garmentId)
        } else {
            ids = wornGarmentIds
        }
        let names = ids.compactMap { id in
            garments.first(where: { $0.id == id })?.displayName
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .filter { !$0.isEmpty }
        if names.isEmpty { return nil }
        if names.count == 1 { return names[0] }
        return names.joined(separator: ", ")
    }
}

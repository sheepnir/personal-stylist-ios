import Foundation

enum StubReadiness: String, Codable, Sendable {
    case ready = "READY"
    case draft = "DRAFT"
}

enum StubSlot: String, Codable, CaseIterable, Sendable {
    case top = "TOP"
    case midLayer = "MID_LAYER"
    case jacket = "JACKET"
    case outerwear = "OUTERWEAR"
    case bottom = "BOTTOM"
    case footwear = "FOOTWEAR"
    case accessory = "ACCESSORY"

    /// UI label — never show raw enum (filter-chip-labels / demo-ux-polish).
    var displayLabel: String {
        switch self {
        case .top: return "Top"
        case .midLayer: return "Mid layer"
        case .jacket: return "Jacket"
        case .outerwear: return "Outerwear"
        case .bottom: return "Bottom"
        case .footwear: return "Footwear"
        case .accessory: return "Accessory"
        }
    }

    /// Shared board and wardrobe slot order (#112 — Outerwear → … → Accessory).
    var wearingOrderIndex: Int { Self.wearingOrder.firstIndex(of: self)! }

    static let wearingOrder: [StubSlot] = [
        .outerwear, .jacket, .midLayer, .top, .bottom, .footwear, .accessory,
    ]
}

struct StubColorPrimary: Codable, Hashable, Sendable {
    var family: String?
    var hex: String?
    var name: String?
}

/// Fixture / UI DTO mapped to/from SwiftData `GarmentEntity` (M0-11).
struct StubGarment: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var displayName: String
    var slot: StubSlot
    var readiness: StubReadiness
    var availability: String
    var colorPrimary: StubColorPrimary?
    var pattern: String?
    var surface: String?
    var imagePath: String?
    var formality: Int?
    var warmth: Int?
    var setId: UUID?
    var keepTogether: Bool?
    /// ISO date `YYYY-MM-DD` from fixtures, or nil if never worn.
    var lastWornOn: String?
    var daysSinceIntake: Int?
    /// Local intake timestamp; optional for older serialized DTOs.
    var createdAt: Date? = nil
    /// USER | DERIVED — D-31: user-set names are never overwritten.
    var displayNameSource: String = "DERIVED"
    var purchasePrice: Decimal? = nil
    var purchaseCurrency: String? = nil
    var purchaseDate: Date? = nil
    var priorWearBucket: String? = nil
    var priorWearEstimate: Int? = nil
    /// Field → USER | MODEL. Edited readiness fields are USER (D-72).
    var attributeSource: [String: String] = [:]

    var availabilityToken: AvailabilityToken { AvailabilityToken(raw: availability) }
    var isReady: Bool { readiness == .ready }
    var isUserPhoto: Bool { UserGarmentPhotoStore.isUserPhoto(imagePath) }

    /// D-72 / §7.8 — persist positive prices only. Blank or non-positive is nil, never 0.
    static func persistedPurchasePrice(_ price: Decimal?) -> Decimal? {
        guard let price, price > 0 else { return nil }
        return price
    }

    static func untitledName(for slot: StubSlot) -> String {
        "Untitled \(slot.displayLabel)"
    }

    /// Capture one reference date per sort so missing legacy dates compare consistently.
    func intakeSortDate(referenceDate: Date) -> Date {
        createdAt ?? referenceDate.addingTimeInterval(-Double(max(0, daysSinceIntake ?? 0)) * 86_400)
    }

    /// Never-worn sorts first for "longest since worn".
    var lastWornSortKey: Date {
        if let lastWornOn,
           let d = StubGarment.dayFormatter.date(from: lastWornOn) {
            return d
        }
        return Date.distantPast
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}


/// Fixture set (keep-together partners).
struct StubSet: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var displayName: String
    var keepTogether: Bool
    var memberGarmentIds: [UUID]
    var notes: String?
}

struct StubOutfitAssignment: Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var slot: StubSlot
    var garmentId: UUID?
    var gapReason: String?
    var isAnchor: Bool
    var isLocked: Bool = false

    /// Placeholder tile while generate is in flight (#112).
    static let skeletonMarker = "__SKELETON__"

    var isSkeletonPlaceholder: Bool { gapReason == Self.skeletonMarker && garmentId == nil }

    var hasGap: Bool { gapReason != nil && garmentId == nil && !isSkeletonPlaceholder }
}

struct StubOutfit: Identifiable, Hashable, Sendable {
    var id: UUID
    var assignments: [StubOutfitAssignment]
    var rationaleSummary: String
    var offlineCached: Bool
}

struct StubWearEvent: Identifiable, Hashable, Sendable {
    var id: UUID
    var garmentIds: [UUID]
    var wornOn: Date
    var voidedAt: Date? = nil
    var sourceOutfitId: UUID? = nil

    var isVoided: Bool { voidedAt != nil }
}

/// DEMO wear rules — PRD §7.7 AC-2/AC-3 spirit: one active wear per calendar day;
/// re-confirm is a no-op; a different log voids and replaces today's event.
enum WearLogging {
    struct ConfirmResult {
        var event: StubWearEvent?
        var voided: [StubWearEvent]
        var message: String
        var statusLine: String
        var didWrite: Bool
    }

    struct UndoResult {
        var updated: [StubWearEvent]
        var message: String
        var statusLine: String
    }

    static func activeSameDay(
        events: [StubWearEvent],
        day: Date,
        calendar: Calendar = .current
    ) -> [StubWearEvent] {
        events.filter { !$0.isVoided && calendar.isDate($0.wornOn, inSameDayAs: day) }
    }

    /// Newest non-voided event on the user's local calendar date. Time zone only
    /// changes which date "today" is — it does not rewrite historical `wornOn`.
    static func loggedToday(
        events: [StubWearEvent],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> StubWearEvent? {
        activeSameDay(events: events, day: now, calendar: calendar)
            .max(by: { $0.wornOn < $1.wornOn })
    }

    static func confirm(
        existing: [StubWearEvent],
        garmentIds: [UUID],
        wornOn: Date,
        sourceOutfitId: UUID?,
        calendar: Calendar = .current
    ) -> ConfirmResult {
        let incoming = Set(garmentIds)
        let today = activeSameDay(events: existing, day: wornOn, calendar: calendar)
        if today.contains(where: { Set($0.garmentIds) == incoming }) {
            return ConfirmResult(
                event: nil,
                voided: [],
                message: "Already logged today",
                statusLine: "Already logged today",
                didWrite: false
            )
        }

        let voided = today.map { ev -> StubWearEvent in
            var copy = ev
            copy.voidedAt = wornOn
            return copy
        }
        let event = StubWearEvent(
            id: UUID(),
            garmentIds: garmentIds,
            wornOn: wornOn,
            voidedAt: nil,
            sourceOutfitId: sourceOutfitId
        )
        if voided.isEmpty {
            let n = garmentIds.count
            return ConfirmResult(
                event: event,
                voided: [],
                message: "Logged \(n) READY garment\(n == 1 ? "" : "s") as worn.",
                statusLine: "Wear confirmed",
                didWrite: true
            )
        }
        return ConfirmResult(
            event: event,
            voided: voided,
            message: "Replaced this morning's log",
            statusLine: "Wear replaced",
            didWrite: true
        )
    }

    /// Void today's active event; if it replaced an earlier same-day log, restore that one.
    static func undoToday(
        events: [StubWearEvent],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> UndoResult? {
        let todayActive = activeSameDay(events: events, day: now, calendar: calendar)
        guard var latest = todayActive.max(by: { $0.wornOn < $1.wornOn }) else { return nil }
        latest.voidedAt = now

        // Restore only events this confirm voided (voidedAt == this event's wornOn).
        // Do not revive a log the user already undid.
        let previouslyVoided = events
            .filter {
                $0.isVoided
                    && $0.id != latest.id
                    && $0.voidedAt == latest.wornOn
            }
            .sorted { ($0.voidedAt ?? .distantPast) > ($1.voidedAt ?? .distantPast) }

        var updated = [latest]
        if var restored = previouslyVoided.first {
            restored.voidedAt = nil
            updated.append(restored)
            return UndoResult(
                updated: updated,
                message: "Restored this morning's log",
                statusLine: "Wear undone"
            )
        }
        return UndoResult(
            updated: updated,
            message: "Wear undone",
            statusLine: "Wear undone"
        )
    }

    static func counts(from events: [StubWearEvent]) -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for ev in events where !ev.isVoided {
            for gid in ev.garmentIds {
                counts[gid, default: 0] += 1
            }
        }
        return counts
    }

    /// Max `wornOn` per garment from non-voided events.
    static func lastWornOnByGarment(events: [StubWearEvent]) -> [UUID: Date] {
        var latest: [UUID: Date] = [:]
        for ev in events where !ev.isVoided {
            for gid in ev.garmentIds {
                if let existing = latest[gid] {
                    if ev.wornOn > existing { latest[gid] = ev.wornOn }
                } else {
                    latest[gid] = ev.wornOn
                }
            }
        }
        return latest
    }

    static func isoDay(from date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func parseISODay(_ raw: String) -> Date? {
        StubGarment.dayFormatter.date(from: raw)
    }
}

struct WearAggregates: Sendable, Equatable {
    var counts: [UUID: Int]
    var lastWorn: [UUID: Date]
}

struct StubStyleProfile: Identifiable, Hashable, Sendable {
    var id: UUID
    var age: Int?
    var profession: String?
    var workEnvironment: String?
    var workEnvironmentLabel: String?
    var typicalWeekNotes: String?
    var goals: [String]
    var constraintsNotes: String?
    var experimentationLevel: Int?
    var summary: String?
    /// User-owned after first edit of summary text (M1-F01-03 later).
    var summaryUserOwned: Bool
    var version: Int
    var confirmedAt: Date?
    var seedSource: String?

    var isDraft: Bool { confirmedAt == nil }
    var isConfirmed: Bool { confirmedAt != nil }
}

struct StubSwapAlternative: Identifiable, Hashable, Sendable {
    var id: UUID
    var garment: StubGarment
    var reason: String
    var score: Double?
    /// When non-empty, apply all partner garment ids atomically (keepTogether).
    var setPartnerIds: [UUID]
}

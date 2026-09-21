import Foundation

/// Size classes for garment imagery (#119 / claude-review-batch §6).
enum GarmentImagePresentation: Equatable, Sendable {
    case tiny
    case card
    case hero

    static func inferred(from height: CGFloat) -> GarmentImagePresentation {
        if height < 100 { return .tiny }
        if height >= 240 { return .hero }
        return .card
    }
}

/// Colour families for Finish details + card swatches (#123).
struct ColorFamilyOption: Identifiable, Hashable, Sendable {
    var id: String
    var label: String
    var hex: String
    var isSplit: Bool
    var isPrimary: Bool

    init(id: String, label: String, hex: String, isSplit: Bool = false, isPrimary: Bool = true) {
        self.id = id
        self.label = label
        self.hex = hex
        self.isSplit = isSplit
        self.isPrimary = isPrimary
    }
}

enum ColorFamilyCatalog {
    static let all: [ColorFamilyOption] = [
        .init(id: "white", label: "White", hex: "#F5F5F0"),
        .init(id: "cream", label: "Cream", hex: "#E8DCC8"),
        .init(id: "grey", label: "Grey", hex: "#8A8A8A"),
        .init(id: "charcoal", label: "Charcoal", hex: "#3C3C3C"),
        .init(id: "black", label: "Black", hex: "#1A1A1A"),
        .init(id: "navy", label: "Navy", hex: "#1B2A4A"),
        .init(id: "blue", label: "Blue", hex: "#2F5D9F"),
        .init(id: "light_blue", label: "Light blue", hex: "#8FB8D6"),
        .init(id: "olive", label: "Olive", hex: "#6B7A3D"),
        .init(id: "green", label: "Green", hex: "#2F6B4F"),
        .init(id: "brown", label: "Brown", hex: "#6B4423"),
        .init(id: "tan", label: "Tan", hex: "#C4A574"),
        .init(id: "burgundy", label: "Burgundy", hex: "#6E2A36"),
        .init(id: "red", label: "Red", hex: "#A33B32"),
        .init(id: "pink", label: "Pink", hex: "#C9869A"),
        .init(id: "multi", label: "Multi", hex: "#6B7A8A", isSplit: true),
        .init(id: "orange", label: "Orange", hex: "#C46A2B", isPrimary: false),
        .init(id: "yellow", label: "Yellow", hex: "#D4B84A", isPrimary: false),
        .init(id: "purple", label: "Purple", hex: "#5E3A7A", isPrimary: false),
        .init(id: "indigo", label: "Indigo", hex: "#3D3A8A", isPrimary: false),
    ]

    static var primary: [ColorFamilyOption] { all.filter(\.isPrimary) }
    static var more: [ColorFamilyOption] { all.filter { !$0.isPrimary } }

    static func match(family: String?, name: String?, hex: String?) -> ColorFamilyOption? {
        if let hex, let exact = all.first(where: { $0.hex.compare(hex, options: .caseInsensitive) == .orderedSame }) {
            return exact
        }
        let keys = [family, name].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        for key in keys {
            let folded = key.lowercased().replacingOccurrences(of: " ", with: "_")
            if let hit = all.first(where: { $0.id == folded || $0.label.lowercased() == key.lowercased() }) {
                return hit
            }
        }
        return nil
    }

    static func resolvedHex(family: String?, name: String?, hex: String?) -> String? {
        if let hex, hex.count >= 6 { return hex }
        return match(family: family, name: name, hex: hex)?.hex
    }
}

/// PRD §7.2 generation minimum — counts READY and not retired only (#133).
enum WardrobeCoverage {
    static let generationMinimum: [(StubSlot, Int)] = [
        (.top, 2),
        (.bottom, 2),
        (.footwear, 1),
    ]

    struct MissingSlot: Equatable, Sendable {
        var slot: StubSlot
        var have: Int
        var need: Int
    }

    struct Snapshot: Equatable, Sendable {
        var missing: [MissingSlot]
        var draftCount: Int
        var layerCount: Int
        var totalUsable: Int

        var meetsGenerationMinimum: Bool { missing.isEmpty }
        var isEmptyWardrobe: Bool { totalUsable == 0 && draftCount == 0 }
        var isThin: Bool { meetsGenerationMinimum && layerCount == 0 }

        var coverageLine: String? {
            guard !meetsGenerationMinimum else { return nil }
            return WardrobeCoverage.coverageLine(missing: missing)
        }

        var thinSuggestion: String? {
            guard isThin else { return nil }
            return "Add a jacket to unlock smarter work outfits."
        }

        var draftsLine: String? {
            guard draftCount > 0 else { return nil }
            if draftCount == 1 {
                return "1 garment needs details before it can be used"
            }
            return "\(draftCount) garments need details before they can be used"
        }
    }

    static func isUsable(_ garment: StubGarment) -> Bool {
        garment.isReady && garment.availabilityToken != .retired
    }

    static func evaluate(_ garments: [StubGarment]) -> Snapshot {
        let usable = garments.filter(isUsable)
        let drafts = garments.filter { !$0.isReady }
        let bySlot = Dictionary(grouping: usable, by: \.slot)
        let missing = generationMinimum.compactMap { slot, need -> MissingSlot? in
            let have = bySlot[slot]?.count ?? 0
            guard have < need else { return nil }
            return MissingSlot(slot: slot, have: have, need: need)
        }
        let layers = usable.filter { $0.slot == .jacket || $0.slot == .outerwear || $0.slot == .midLayer }.count
        return Snapshot(
            missing: missing,
            draftCount: drafts.count,
            layerCount: layers,
            totalUsable: usable.count
        )
    }

    static func coverageLine(missing: [MissingSlot]) -> String {
        let phrases = missing.map { item in
            phrase(slot: item.slot, remaining: item.need - item.have, have: item.have)
        }
        return "Add \(join(phrases)) and I can build outfits."
    }

    static func phrase(slot: StubSlot, remaining: Int, have: Int = 0) -> String {
        let more = have > 0
        switch slot {
        case .top:
            if remaining == 1 { return more ? "1 more top" : "1 top" }
            return more ? "\(remaining) more tops" : "\(remaining) tops"
        case .bottom:
            if remaining == 1 { return more ? "1 more pair of trousers or jeans" : "1 pair of trousers or jeans" }
            return more ? "\(remaining) more pairs of trousers or jeans" : "\(remaining) pairs of trousers or jeans"
        case .footwear:
            if remaining == 1 { return more ? "1 more pair of footwear" : "1 pair of footwear" }
            return more ? "\(remaining) more pairs of footwear" : "\(remaining) pairs of footwear"
        default:
            let label = slot.displayLabel.lowercased()
            if remaining == 1 { return more ? "1 more \(label)" : "1 \(label)" }
            return more ? "\(remaining) more \(label)s" : "\(remaining) \(label)s"
        }
    }

    private static func join(_ parts: [String]) -> String {
        switch parts.count {
        case 0: return ""
        case 1: return parts[0]
        case 2: return "\(parts[0]) and \(parts[1])"
        default: return parts.dropLast().joined(separator: ", ") + ", and " + parts.last!
        }
    }
}

/// Editable profile field vocab — PRD §7.1, no seed-specific literals (#124).
enum ProfileFieldCopy {
    struct WorkEnvironmentOption: Identifiable, Hashable, Sendable {
        var id: String
        var label: String
    }

    static let workEnvironments: [WorkEnvironmentOption] = [
        .init(id: "FORMAL_OFFICE", label: "Suit or jacket most days"),
        .init(id: "BUSINESS_CASUAL", label: "Jacket for meetings, relaxed otherwise"),
        .init(id: "SMART_CASUAL", label: "Neat but casual"),
        .init(id: "CASUAL_TECH", label: "Most people wear jeans and tees"),
        .init(id: "REMOTE", label: "I work from home"),
        .init(id: "MIXED", label: "It changes a lot"),
    ]

    static func workEnvironmentLabel(for id: String?) -> String? {
        guard let id else { return nil }
        return workEnvironments.first(where: { $0.id == id })?.label
    }

    /// Five occasion chips for a typical week (PRD §7.1).
    static let typicalWeekChips: [String] = [
        DayOccasion.workStandard.rawValue,
        DayOccasion.casualDay.rawValue,
        DayOccasion.eveningOut.rawValue,
        DayOccasion.weekendErrands.rawValue,
        DayOccasion.specialEvent.rawValue,
    ]

    static let goalOptions: [String] = [
        "look more polished",
        "wear more of what I own",
        "spend less time deciding",
        "learn what goes together",
        "feel more like myself",
        "dress for the role I want next",
    ]

    static let constraintChips: [String] = [
        "no tight collars",
        "nothing itchy",
        "must be able to walk far",
    ]

    static func parseTypicalWeek(_ notes: String?) -> (selected: Set<String>, extra: String) {
        guard let notes, !notes.isEmpty else { return ([], "") }
        let parts = notes.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        var selected = Set<String>()
        var extra: [String] = []
        for part in parts {
            if typicalWeekChips.contains(part) {
                selected.insert(part)
            } else {
                extra.append(part)
            }
        }
        return (selected, extra.joined(separator: ", "))
    }

    static func encodeTypicalWeek(selected: Set<String>, extra: String) -> String? {
        let chips = typicalWeekChips.filter { selected.contains($0) }
        let extraTrimmed = extra.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts = chips
        if !extraTrimmed.isEmpty { parts.append(extraTrimmed) }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    static func splitGoals(_ goals: [String]) -> (selected: Set<String>, extra: String) {
        var selected = Set<String>()
        var extra: [String] = []
        for goal in goals {
            let trimmed = goal.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if goalOptions.contains(trimmed) {
                selected.insert(trimmed)
            } else {
                extra.append(trimmed)
            }
        }
        return (selected, extra.joined(separator: ", "))
    }

    static func encodeGoals(selected: Set<String>, extra: String) -> [String] {
        var result = goalOptions.filter { selected.contains($0) }
        let extraTrimmed = extra.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extraTrimmed.isEmpty { result.append(extraTrimmed) }
        return result
    }

    static func splitConstraints(_ notes: String?) -> (selected: Set<String>, extra: String) {
        guard let notes, !notes.isEmpty else { return ([], "") }
        var selected = Set<String>()
        // Only recognize complete leading chip tokens emitted by encodeConstraints.
        // Never remove words from a free-text sentence (including negations).
        var extra = notes
        while let chip = constraintChips.first(where: {
            extra == $0 || extra.hasPrefix($0 + ". ")
        }) {
            selected.insert(chip)
            extra = extra == chip ? "" : String(extra.dropFirst(chip.count + 2))
        }
        return (selected, extra)
    }

    static func encodeConstraints(selected: Set<String>, extra: String) -> String? {
        var parts = constraintChips.filter { selected.contains($0) }
        let extraTrimmed = extra.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extraTrimmed.isEmpty { parts.append(extraTrimmed) }
        return parts.isEmpty ? nil : parts.joined(separator: ". ")
    }
}

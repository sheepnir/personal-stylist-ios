import Foundation

/// Editor colour state for Finish details (#279).
/// Catalog picks use canonical family/hex/name. Unknown/custom values stay as stored.
struct FinishDetailsColorState: Equatable, Sendable {
    var familyId: String
    var hex: String
    var displayName: String

    var catalogOption: ColorFamilyOption? {
        ColorFamilyCatalog.all.first(where: { $0.id == familyId })
    }

    var isCustom: Bool {
        hasColor && catalogOption == nil
    }

    /// Swatch identity for ready-save: catalog/custom family and/or hex.
    /// The optional colour name alone is not enough.
    var hasColor: Bool {
        !trimmed(familyId).isEmpty || !trimmed(hex).isEmpty
    }

    var accessibilityLabel: String {
        let name = trimmed(displayName)
        if !name.isEmpty { return name }
        let family = trimmed(familyId)
        if !family.isEmpty { return family }
        return "Custom colour"
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum FinishDetailsColorDraft {
    static func seed(from color: StubColorPrimary?) -> FinishDetailsColorState {
        guard let color else {
            return FinishDetailsColorState(familyId: "", hex: "", displayName: "")
        }
        let family = color.family?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hex = color.hex?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = color.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return FinishDetailsColorState(familyId: family, hex: hex, displayName: name)
    }

    /// Explicit catalog tap — replace custom or previous catalog values with canonical ones.
    static func selectingCatalog(_ option: ColorFamilyOption) -> FinishDetailsColorState {
        FinishDetailsColorState(familyId: option.id, hex: option.hex, displayName: option.label)
    }

    static func editingName(_ name: String, previous: FinishDetailsColorState) -> FinishDetailsColorState {
        var next = previous
        next.displayName = name
        return next
    }

    static func persistColor(from state: FinishDetailsColorState) -> StubColorPrimary {
        let family = nilIfEmpty(state.familyId)
        let hex = nilIfEmpty(state.hex)
        var name = nilIfEmpty(state.displayName)
        if name == nil, let option = state.catalogOption {
            name = option.label
        }
        return StubColorPrimary(family: family, hex: hex, name: name)
    }

    static func previewColor(from state: FinishDetailsColorState) -> StubColorPrimary? {
        guard state.hasColor else { return nil }
        return persistColor(from: state)
    }

    static func missingColor(_ state: FinishDetailsColorState) -> Bool {
        !state.hasColor
    }

    /// Ready-save / persist gate: family or hex. Name alone is not a swatch.
    static func hasSwatchIdentity(_ color: StubColorPrimary) -> Bool {
        let family = color.family?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hex = color.hex?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !family.isEmpty || !hex.isEmpty
    }

    private static func nilIfEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

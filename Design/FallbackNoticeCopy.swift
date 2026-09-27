import Foundation

/// #45 / #46 (iOS-A2 / iOS-A3) — "Built without the AI stylist" notice on the board.
/// Designer spec 0001 rev 3 §2.4 (exact strings; changes need Designer sign-off).
/// Keyed on the **presence** of the stored `fallbackReason`, never on `fallbackLevel`
/// (ADR-0001 §10.4). Raw reason values and `promptVersion` never reach the UI (R10).
enum FallbackNoticeCopy {
    /// `fallbackNoticeTitle`
    static let title = "Built without the AI stylist"
    /// `fallbackNoticeUnavailable` — `PROVIDER_ERROR`
    static let unavailable = "The AI stylist wasn't available, so the app put this one together from your wardrobe."
    /// `fallbackNoticeNoUsableOutfit` — `INVALID_OUTPUT`
    static let noUsableOutfit = "The AI stylist couldn't come up with a usable outfit this time, so the app put this one together from your wardrobe."
    /// `fallbackNoticeLimit` — `SPEND_CAP`
    static let limit = "The AI stylist reached its usage limit, so the app put this one together from your wardrobe."
    /// `fallbackNoticeLimitResetUnknown` — `SPEND_CAP` Variant B (R11). No reset time, no usage call.
    static let limitResetUnknown = "It'll be back after the limit resets."
    /// `fallbackNoticeGeneric` — any other present value (unrecognised, empty, undecodable).
    static let generic = "This time the app put this outfit together from your wardrobe on its own."

    enum Reason: Equatable {
        case providerError
        case invalidOutput
        case spendCap
        /// Present but not one of the three mapped values.
        case other
    }

    /// `nil` when the field is absent (no notice). Exact, case-sensitive match (R10).
    static func reason(for stored: String?) -> Reason? {
        guard let stored else { return nil }
        switch stored {
        case "PROVIDER_ERROR": return .providerError
        case "INVALID_OUTPUT": return .invalidOutput
        case "SPEND_CAP": return .spendCap
        default: return .other
        }
    }

    static func body(for reason: Reason) -> String {
        switch reason {
        case .providerError: return unavailable
        case .invalidOutput: return noUsableOutfit
        case .spendCap: return "\(limit) \(limitResetUnknown)"
        case .other: return generic
        }
    }

    /// VoiceOver label for the single combined element; also the announcement text.
    static func accessibilityLabel(body: String) -> String {
        "\(title). \(body)"
    }

    static func notice(for generation: OutfitGenerationMetadata?) -> FallbackNotice? {
        guard let reason = reason(for: generation?.fallbackReason) else { return nil }
        let body = body(for: reason)
        return FallbackNotice(
            reason: reason,
            title: title,
            body: body,
            accessibilityLabel: accessibilityLabel(body: body)
        )
    }
}

struct FallbackNotice: Equatable {
    var reason: FallbackNoticeCopy.Reason
    var title: String
    var body: String
    var accessibilityLabel: String
}

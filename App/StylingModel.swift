import Foundation

enum StylingModel: String, CaseIterable, Identifiable {
    case jev = "typesafe/jev-1.13"
    case luna = "openai/gpt-5.6-luna"

    static let defaultsKey = "styling.selectedModel"
    static let lunaConsentKey = "styling.lunaAcceptedPolicyVersion"
    static let lunaPolicyVersion = "luna-text-v1"
    var id: String { rawValue }
    var title: String { self == .jev ? "Jev 1.13" : "GPT-5.6 Luna" }

    static func selected(in defaults: UserDefaults = .standard) -> StylingModel {
        StylingModel(rawValue: defaults.string(forKey: defaultsKey) ?? "") ?? .jev
    }
    static func applyHeaders(to request: inout URLRequest, defaults: UserDefaults = .standard) {
        let model = selected(in: defaults)
        request.setValue(model.rawValue, forHTTPHeaderField: "X-Styling-Model")
        let policy = model == .jev ? StylingConsent.acceptedVersion(in: defaults) :
            (defaults.string(forKey: lunaConsentKey) == lunaPolicyVersion ? lunaPolicyVersion : nil)
        request.setValue(policy, forHTTPHeaderField: "X-Styling-Policy")
    }
    static func swapNotice(_ metadata: SwapSelectionMetadata) -> String? {
        if metadata.fallbackReason != nil {
            return "The AI stylist couldn’t choose a swap this time. These suggestions follow your wardrobe rules."
        }
        guard metadata.fallbackLevel == "NONE" else { return nil }
        return "\(resultTitle(metadata.modelId)) chose the first suggestion. You can choose any option below."
    }
    static func swapSummary(_ metadata: SwapSelectionMetadata?) -> String {
        guard let metadata, metadata.fallbackLevel == "NONE", metadata.selectedSuggestedOption else { return "Updated after swap." }
        return "Updated with \(resultTitle(metadata.modelId))’s suggested swap."
    }
    static func resultTitle(_ id: String?) -> String {
        guard let id else { return "Wardrobe rules" }
        if id == jev.rawValue || id.hasPrefix(jev.rawValue + "-") { return jev.title }
        if id == luna.rawValue || id.hasPrefix(luna.rawValue + "-") { return luna.title }
        return "Wardrobe rules"
    }
}

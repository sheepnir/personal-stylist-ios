import SwiftUI

struct StylingConsentSection: View {
    @AppStorage(StylingConsent.defaultsKey) private var acceptedVersion = ""
    @AppStorage(StylingModel.lunaConsentKey) private var lunaAcceptedVersion = ""
    @AppStorage(StylingModel.defaultsKey) private var selectedModel = StylingModel.jev.rawValue
    var body: some View {
        Section {
            Picker("Stylist model", selection: $selectedModel) {
                ForEach(StylingModel.allCases) { model in Text(model.title).tag(model.rawValue) }
            }
            Text("With your permission, Jev 1.13 chooses from outfits that already follow your wardrobe rules. OpenRouter and TypeSafe receive the candidates’ clothing slots, color families, formality and warmth, plus your selected occasion, temperature, rain and time of day.")
            Text("Photos, names, notes, profile answers, prices and wear history aren’t sent to Jev. Requests exclude providers that use this data for training. Jev selects an option; the app writes the explanation using wardrobe rules.")
            Toggle("Allow Jev outfit suggestions", isOn: Binding(
                get: { acceptedVersion == StylingConsent.policyVersion },
                set: { acceptedVersion = $0 ? StylingConsent.policyVersion : "" }
            ))
            .accessibilityHint("You can turn this off at any time. Future requests will use wardrobe rules without Jev.")
            Text("For GPT-5.6 Luna, OpenRouter and OpenAI receive the same limited clothing and context attributes described above. Photos, names, notes, profile answers, prices and wear history stay out of requests. Providers that use requests for training are excluded.")
            Toggle("Allow GPT-5.6 Luna suggestions", isOn: Binding(
                get: { lunaAcceptedVersion == StylingModel.lunaPolicyVersion },
                set: { lunaAcceptedVersion = $0 ? StylingModel.lunaPolicyVersion : "" }
            ))
            Text("Only your selected model is called. Both models share the spending limit and select from outfits that follow your wardrobe rules.")
        } header: {
            Text("AI outfit suggestions")
        } footer: {
            Text("If your selected model is unavailable or a spending limit is reached, you still get an outfit using wardrobe rules.")
        }
    }
}

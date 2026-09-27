import SwiftUI

struct StylingConsentSection: View {
    @AppStorage(StylingConsent.defaultsKey) private var acceptedVersion = ""
    var body: some View {
        Section {
            Text("With your permission, Jev 1.13 chooses from outfits that already follow your wardrobe rules. OpenRouter and TypeSafe receive the candidates’ clothing slots, color families, formality and warmth, plus your selected occasion, temperature, rain and time of day.")
            Text("Photos, names, notes, profile answers, prices and wear history aren’t sent to Jev. Requests exclude providers that use this data for training. Jev selects an option; the app writes the explanation using wardrobe rules.")
            Toggle("Allow Jev outfit suggestions", isOn: Binding(
                get: { acceptedVersion == StylingConsent.policyVersion },
                set: { acceptedVersion = $0 ? StylingConsent.policyVersion : "" }
            ))
            .accessibilityHint("You can turn this off at any time. Future requests will use wardrobe rules without Jev.")
        } header: {
            Text("Jev outfit suggestions")
        } footer: {
            Text("If Jev is unavailable or a spending limit is reached, you still get an outfit using wardrobe rules.")
        }
    }
}

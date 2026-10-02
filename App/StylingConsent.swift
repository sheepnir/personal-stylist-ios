import Foundation

/// Mirrored from shared/privacy-policy-version.json; enforced by the parity check.
/// This consent applies only to structured text used for bounded outfit decisions.
/// It never grants permission to send photos or profile fields.
enum StylingConsent {
    static let policyVersion = "jev-text-v1"
    static let defaultsKey = "styling.acceptedPolicyVersion"

    static func acceptedVersion(in defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: defaultsKey) == policyVersion ? policyVersion : nil
    }
}

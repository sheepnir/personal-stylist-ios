import XCTest
@testable import PersonalStylist

final class StylingConsentTests: XCTestCase {
    func testOnlyExactVersionAcceptsAndWithdrawalClearsEligibility() {
        let name = "StylingConsentTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        for value in ["", "old-version", "JEV-TEXT-V1", " jev-text-v1"] {
            defaults.set(value, forKey: StylingConsent.defaultsKey)
            XCTAssertNil(StylingConsent.acceptedVersion(in: defaults))
        }
        defaults.set(StylingConsent.policyVersion, forKey: StylingConsent.defaultsKey)
        XCTAssertEqual(StylingConsent.acceptedVersion(in: defaults), StylingConsent.policyVersion)
        defaults.removeObject(forKey: StylingConsent.defaultsKey)
        XCTAssertNil(StylingConsent.acceptedVersion(in: defaults))
    }
}

import XCTest
import SwiftUI
import UIKit
@testable import PersonalStylist

/// #112: hydration is not an edit. Exercise real appear/disappear callbacks without
/// tapping Save or invoking profile methods directly. Edits use hosted UITextField events.
@MainActor
final class ProfileDraftLifecycleHostedTests: XCTestCase {
    func testOpeningAndDismissingConfirmedProfilePreservesEveryField() async throws {
        try await assertUntouchedVisitPreservesProfile(confirmed: true)
    }

    func testOpeningAndDismissingDraftPreservesNilDefaultsAndCustomFields() async throws {
        try await assertUntouchedVisitPreservesProfile(confirmed: false)
    }

    func testProfessionEditAutosavesOnDismissal() async throws {
        try await assertUntouchedVisitPreservesProfile(confirmed: true, professionChanges: ["Synthetic designer"])
    }

    func testProfessionEditThenRevertPreservesEntireProfile() async throws {
        try await assertUntouchedVisitPreservesProfile(confirmed: true,
            professionChanges: ["Synthetic designer", "Synthetic architect"])
    }

    private func textField(_ view: UIView, text: String) -> UITextField? {
        if let field = view as? UITextField, field.text == text { return field }
        return view.subviews.lazy.compactMap { self.textField($0, text: text) }.first
    }

    private func assertUntouchedVisitPreservesProfile(confirmed: Bool, professionChanges: [String] = []) async throws {
        let suite = "ProfileDraftLifecycleHostedTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = StubStyleProfile(
            id: UUID(), age: 34, profession: "Synthetic architect",
            workEnvironment: "studio", workEnvironmentLabel: "Studio",
            typicalWeekNotes: nil, goals: ["custom synthetic goal", "fewer repeats"],
            constraintsNotes: nil, experimentationLevel: nil, summary: nil,
            summaryUserOwned: false, version: 1,
            confirmedAt: confirmed ? Date(timeIntervalSince1970: 1_758_000_000) : nil,
            seedSource: nil
        )
        let store = InMemoryPersistenceStore(garments: [], sets: [], defaults: defaults)
        try await store.saveStyleProfile(original)
        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()
        XCTAssertEqual(model.styleProfile, original)

        let navigation = UINavigationController(rootViewController: UIViewController())
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.windowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        let host = UIHostingController(rootView: ProfileDraftView(model: model))
        navigation.pushViewController(host, animated: false)
        host.view.layoutIfNeeded()
        // Let the onAppear Task hydrate fields and SwiftUI deliver onChange callbacks.
        try await Task.sleep(for: .milliseconds(800))
        host.view.layoutIfNeeded()
        XCTAssertTrue(navigation.topViewController === host)
        XCTAssertNotNil(host.view.window, "The profile must be hosted onscreen for this lifecycle regression")
        let professionField = try XCTUnwrap(textField(host.view, text: "Synthetic architect"),
                      "Hydration must reach the rendered profession field before dismissal")
        XCTAssertEqual(model.styleProfile, original, "Simply appearing must not change the profile")

        for change in professionChanges {
            professionField.text = change
            professionField.sendActions(for: .editingChanged)
            try await Task.sleep(for: .milliseconds(150))
        }
        XCTAssertTrue(navigation.popViewController(animated: false) === host)
        // Let onDisappear and any autosave Task complete before inspecting persistence.
        try await Task.sleep(for: .milliseconds(800))
        let persisted = await store.fetchStyleProfile()
        if let finalProfession = professionChanges.last, finalProfession != original.profession {
            var expected = original
            expected.profession = finalProfession
            expected.version = 2
            XCTAssertEqual(model.styleProfile, expected, "Only the edited profession and version may change")
            XCTAssertEqual(persisted, expected, "Autosave must preserve unrelated fields and unanswered values")
            return
        }
        XCTAssertEqual(model.styleProfile, original, "An untouched or reverted visit must preserve the entire in-memory profile")
        XCTAssertEqual(persisted, original, "An untouched visit must preserve every persisted profile field")
        XCTAssertEqual(persisted?.version, 1)
        XCTAssertEqual(persisted?.workEnvironmentLabel, "Studio")
        XCTAssertNil(persisted?.experimentationLevel, "A displayed slider default must not become a stored answer")
        XCTAssertNil(persisted?.typicalWeekNotes)
        XCTAssertNil(persisted?.constraintsNotes)
        XCTAssertNil(persisted?.summary)
    }
}

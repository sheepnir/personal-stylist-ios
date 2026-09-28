import XCTest
import SwiftUI
import UIKit
@testable import PersonalStylist

/// Sprint 9 (#124) — tab-shell guarantees with real hosted appear/disappear callbacks:
/// opening the Outfit tab never generates, and leaving the Profile tab never saves or
/// discards edits silently.
@MainActor
final class TabShellHostedTests: XCTestCase {
    private var window: UIWindow?

    override func tearDown() {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        super.tearDown()
    }

    // MARK: - Outfit tab

    func testOutfitBoardUnderTabShellDoesNotGenerateOnAppear() async throws {
        let (model, _) = try await makeModel(confirmedProfile: true)
        XCTAssertNil(model.outfit)
        let host = UIHostingController(rootView: NavigationStack {
            OutfitBoardView(model: model, onSwap: { _ in }, onWear: {}, autoBuildsOnAppear: false)
        })
        show(host)
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertNil(model.outfit, "opening the Outfit tab must not build an outfit")
        XCTAssertFalse(model.isGenerating)
        XCTAssertNil(model.generateIntent)
    }

    func testEmptyOutfitTabRendersWithoutGenerating() async throws {
        let (model, _) = try await makeModel(confirmedProfile: true)
        let host = UIHostingController(rootView: NavigationStack {
            OutfitEmptyStateView(hasLoggedToday: false, onChooseStartingItem: {}, onOpenLoggedToday: {})
        })
        show(host)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertNil(model.outfit)
        XCTAssertFalse(model.isGenerating)
        XCTAssertNil(model.generateIntent)
    }

    // MARK: - Profile tab leave guard

    func testLeavingProfileTabKeepsEditsUnsavedUntilExplicitSave() async throws {
        let (model, store) = try await makeModel(confirmedProfile: true)
        let original = try XCTUnwrap(model.styleProfile)
        let box = CommandBox()
        let host = UIHostingController(rootView: TabProfileHarness(model: model, box: box))
        show(host)
        try await Task.sleep(for: .milliseconds(800))
        let field = try XCTUnwrap(textField(host.view, text: "Synthetic architect"))
        field.text = "Synthetic designer"
        field.sendActions(for: .editingChanged)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(box.dirty, "the shell learns about unsaved edits")

        // Switching tabs removes the profile from screen: no autosave.
        window?.rootViewController = UIViewController()
        try await Task.sleep(for: .milliseconds(500))
        let afterLeave = await store.fetchStyleProfile()
        XCTAssertEqual(afterLeave, original, "leaving the tab must not save silently")
        XCTAssertEqual(model.styleProfile, original)

        // Coming back keeps the draft; an explicit Save persists only the edit.
        window?.rootViewController = host
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(box.dirty, "the draft is not discarded silently either")
        box.command = ProfileEditorCommand(action: .save)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(box.handled.map(\.action), [.save])
        var expected = original
        expected.profession = "Synthetic designer"
        expected.version = original.version + 1
        let persisted = await store.fetchStyleProfile()
        XCTAssertEqual(persisted, expected)
        XCTAssertFalse(box.dirty)
    }

    func testDiscardRestoresSavedValuesWithoutWriting() async throws {
        let (model, store) = try await makeModel(confirmedProfile: true)
        let original = try XCTUnwrap(model.styleProfile)
        let box = CommandBox()
        let host = UIHostingController(rootView: TabProfileHarness(model: model, box: box))
        show(host)
        try await Task.sleep(for: .milliseconds(800))
        let field = try XCTUnwrap(textField(host.view, text: "Synthetic architect"))
        field.text = "Synthetic designer"
        field.sendActions(for: .editingChanged)
        try await Task.sleep(for: .milliseconds(200))
        box.command = ProfileEditorCommand(action: .discard)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(box.handled.map(\.action), [.discard])
        XCTAssertFalse(box.dirty)
        XCTAssertNotNil(textField(host.view, text: "Synthetic architect"), "fields return to the saved values")
        let persisted = await store.fetchStyleProfile()
        XCTAssertEqual(persisted, original)
    }

    // MARK: - Helpers

    private final class CommandBox: ObservableObject {
        @Published var command: ProfileEditorCommand?
        @Published var dirty = false
        var handled: [ProfileEditorCommand] = []
    }

    private struct TabProfileHarness: View {
        let model: LoopDemoModel
        @ObservedObject var box: CommandBox

        var body: some View {
            NavigationStack {
                ProfileDraftView(
                    model: model,
                    autosavesOnDisappear: false,
                    onUnsavedChangesChange: { box.dirty = $0 },
                    pendingCommand: box.command,
                    onCommandHandled: { command in
                        box.handled.append(command)
                        box.command = nil
                    }
                )
            }
        }
    }

    private func makeModel(confirmedProfile: Bool) async throws -> (LoopDemoModel, InMemoryPersistenceStore) {
        let suite = "TabShellHostedTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let store = InMemoryPersistenceStore(garments: [], sets: [], defaults: defaults)
        try await store.saveStyleProfile(
            StubStyleProfile(
                id: UUID(), age: 34, profession: "Synthetic architect",
                workEnvironment: nil, workEnvironmentLabel: nil,
                typicalWeekNotes: nil, goals: [], constraintsNotes: nil,
                experimentationLevel: nil, summary: nil, summaryUserOwned: false, version: 1,
                confirmedAt: confirmedProfile ? Date(timeIntervalSince1970: 1_758_000_000) : nil,
                seedSource: nil
            )
        )
        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()
        return (model, store)
    }

    private func show(_ controller: UIViewController) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.windowScene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        self.window = window
    }

    private func textField(_ view: UIView, text: String) -> UITextField? {
        if let field = view as? UITextField, field.text == text { return field }
        return view.subviews.lazy.compactMap { self.textField($0, text: text) }.first
    }
}

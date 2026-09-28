import XCTest
import SwiftUI
import UIKit
@testable import PersonalStylist

/// Actual UIWindow hit testing before dispatching an action: accessibilityActivate and
/// sending actions directly to a discovered button would miss photo interception.
@MainActor
final class BoardPhotoHitTestingHostedTests: XCTestCase {
    func testFixtureBoardSwapAndKeepReceiveVisibleCenterHits() async throws {
        try await verifyBoardHits(photo: false)
    }

    func testLargePortraitPhotoBoardSwapAndKeepReceiveVisibleCenterHits() async throws {
        try await verifyBoardHits(photo: true)
    }

    func testLargePortraitPhotoBoardKeepReceivesVisibleCenterHit() async throws {
        try await verifyBoardHits(photo: true, testSwap: false)
    }

    private func descendants<T: UIView>(_ root: UIView, as type: T.Type) -> [T] {
        (root as? T).map { [$0] } ?? [] + root.subviews.flatMap { descendants($0, as: type) }
    }

    private func verifyBoardHits(photo: Bool, testSwap: Bool = true) async throws {
        let suite = "BoardPhotoHitTestingHostedTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var garments = [garment("Synthetic top", .top), garment("Synthetic bottom", .bottom), garment("Synthetic shoes", .footwear)]
        var paths: [String] = []
        defer { paths.forEach { UserGarmentPhotoStore.removeFile(imagePath: $0) } }
        if photo {
            // A deliberately tall synthetic camera image, with no personal photo input.
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let image = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 4000), format: format).image { context in
                UIColor.systemIndigo.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 1200, height: 4000))
            }
            let data = try XCTUnwrap(image.jpegData(compressionQuality: 0.8))
            for index in garments.indices {
                let path = try UserGarmentPhotoStore.persistJPEG(from: data, garmentId: garments[index].id)
                paths.append(path)
                garments[index].imagePath = path
                XCTAssertNotNil(UserGarmentPhotoStore.loadThumbnail(imagePath: path, maxPixel: 540))
            }
        }
        let store = InMemoryPersistenceStore(garments: garments, sets: [], defaults: defaults)
        let model = LoopDemoModel(store: store, preferences: defaults)
        await model.load()
        let assignments = garments.enumerated().map { index, garment in
            StubOutfitAssignment(slot: garment.slot, garmentId: garment.id, gapReason: nil, isAnchor: index == 0, isLocked: false)
        }
        model.outfit = StubOutfit(id: UUID(), assignments: assignments, rationaleSummary: "Synthetic hit test", offlineCached: false)
        model.outfitWearable = true
        var swapped: StubSlot?
        let host = UIHostingController(rootView: OutfitBoardView(model: model, onSwap: { swapped = $0 }, onWear: {})
            .defaultAppStorage(defaults))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.windowScene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(800))
        let scroll = try XCTUnwrap(descendants(host.view, as: UIScrollView.self).first)
        let swap = try XCTUnwrap(descendants(host.view, as: HostedDailyWearA11yButton.self).first { $0.accessibilityLabel == "Swap" })
        let rect = swap.convert(swap.bounds, to: scroll)
        let maximumOffset = max(0, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
        scroll.setContentOffset(CGPoint(x: 0, y: min(maximumOffset, max(0, rect.midY - 250))), animated: false)
        try await Task.sleep(for: .milliseconds(300))
        host.view.layoutIfNeeded()
        if testSwap {
            try activateVisibleHit(swap, in: window)
            XCTAssertEqual(swapped, .bottom, "The visible Swap tap must reach its board callback")
        }

        let keep = try XCTUnwrap(descendants(host.view, as: HostedDailyWearA11yButton.self).first { $0.accessibilityLabel == "Keep" })
        try activateVisibleHit(keep, in: window)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(model.outfit?.assignments.first { $0.id == assignments[1].id }?.isLocked, true)
        let unlock = try XCTUnwrap(descendants(host.view, as: HostedDailyWearA11yButton.self).first { $0.accessibilityLabel == "Unlock" })
        try activateVisibleHit(unlock, in: window)
        XCTAssertEqual(model.outfit?.assignments.first { $0.id == assignments[1].id }?.isLocked, false)
    }

    private func activateVisibleHit(_ intended: HostedDailyWearA11yButton, in window: UIWindow) throws {
        let frame = intended.convert(intended.bounds, to: window)
        let point = CGPoint(x: frame.midX, y: frame.midY)
        XCTAssertTrue(window.bounds.insetBy(dx: 0, dy: 90).contains(point), "Control center must be visibly inside the viewport: \(frame)")
        var hit = window.hitTest(point, with: nil)
        let hitDescription = String(describing: hit)
        while let view = hit, !(view is HostedDailyWearA11yButton) { hit = view.superview }
        let target = try XCTUnwrap(hit as? HostedDailyWearA11yButton,
            "Visible \(intended.accessibilityLabel ?? "button") center was intercepted: \(hitDescription)")
        XCTAssertTrue(target === intended, "Hit must resolve to the intended control, not another board action")
        guard target === intended else { return }
        target.sendActions(for: .touchUpInside)
    }

    private func garment(_ name: String, _ slot: StubSlot) -> StubGarment {
        StubGarment(id: UUID(), displayName: name, slot: slot, readiness: .ready, availability: "AVAILABLE",
            colorPrimary: StubColorPrimary(family: "navy", hex: "#1B2A4A", name: "Navy"), pattern: "SOLID", surface: "SMOOTH",
            imagePath: nil, formality: 3, warmth: 3, setId: nil, keepTogether: nil, lastWornOn: nil, daysSinceIntake: 0)
    }
}

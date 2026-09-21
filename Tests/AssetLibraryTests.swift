import XCTest
import SwiftUI
@testable import PersonalStylist

final class AssetLibraryTests: XCTestCase {
    @MainActor
    func testLibraryRendersInLightAndDark() async throws {
        for scheme in [ColorScheme.light, .dark] {
            let preview = AssetLibraryPreview()
                .frame(width: 900, height: 1200)
                .background(scheme == .dark ? Color.black : Color.white)
                .environment(\.colorScheme, scheme)
            // ScrollView needs a hosted layout; ImageRenderer alone can return a blank image.
            let host = UIHostingController(rootView: preview)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 900, height: 1200))
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            host.view.frame = window.bounds
            try await Task.sleep(for: .milliseconds(400))
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let pixels = try XCTUnwrap(image.cgImage?.dataProvider?.data) as Data
            XCTAssertGreaterThan(Set(pixels).count, 10, "Preview must not be a blank background")
            let attachment = XCTAttachment(image: image)
            attachment.name = "Asset library \(scheme)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testAllCatalogResourcesLoadAtRuntime() {
        let colors = ["availability.available", "availability.laundry", "availability.packed",
                      "availability.retired", "availability.cleaners", "availability.stored",
                      "status.draft", "status.gap", "status.success", "status.failure",
                      "status.offline", "status.info", "surface.card", "surface.cardDraft",
                      "surface.badge", "surface.bannerInfo", "surface.bannerWarn",
                      "surface.bannerError", "brand.accent"]
        let images = ["silhouette.top", "silhouette.midLayer", "silhouette.jacket",
                      "silhouette.outerwear", "silhouette.bottom", "silhouette.footwear",
                      "silhouette.accessory", "silhouette.garment", "illustration.captureHang",
                      "illustration.capturePlainBackground", "illustration.captureDaylight",
                      "illustration.emptyWardrobe"]
        for name in colors { XCTAssertNotNil(UIColor(named: name), name) }
        for name in images { XCTAssertNotNil(UIImage(named: name), name) }
    }
}

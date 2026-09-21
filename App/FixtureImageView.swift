import SwiftUI
import UIKit

/// Renders fixture swatches, slot silhouettes, or persisted user photos (#119).
struct FixtureImageView: View {
    let garment: StubGarment
    var height: CGFloat = 160
    var presentation: GarmentImagePresentation? = nil

    private var sizeClass: GarmentImagePresentation {
        presentation ?? GarmentImagePresentation.inferred(from: height)
    }

    var body: some View {
        Group {
            if sizeClass == .hero {
                heroBody
            } else {
                sizedBody(height: height)
            }

        }
    }

    private var heroBody: some View {
        Color.clear
            .aspectRatio(4 / 5, contentMode: .fit)
            .overlay {
                sizedBody(height: nil)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func sizedBody(height: CGFloat?) -> some View {
        ZStack(alignment: badgeAlignment) {
            fillLayer(height: height)
            if showsBadge {
                badge
                    .padding(sizeClass == .tiny ? 4 : 8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: sizeClass == .tiny ? 8 : 12, style: .continuous))
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private func fillLayer(height: CGFloat?) -> some View {
        if let image = displayImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .clipped()
        } else {
            swatchBackground(height: height)
                .overlay {
                    AssetLibrary.Silhouette.slot(garment.slot)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(glyphPadding)
                        .accessibilityHidden(true)
                }
        }
    }

    private func swatchBackground(height: CGFloat?) -> some View {
        let color = swatchColor
        return Group {
            if ColorFamilyCatalog.match(
                family: garment.colorPrimary?.family,
                name: garment.colorPrimary?.name,
                hex: garment.colorPrimary?.hex
            )?.isSplit == true {
                LinearGradient(
                    colors: [color, color.opacity(0.45), Color.white.opacity(0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                LinearGradient(
                    colors: [color, color.opacity(0.72)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    private var glyphPadding: CGFloat {
        switch sizeClass {
        case .tiny: return 10
        case .card: return 28
        case .hero: return 56
        }
    }

    private var badgeAlignment: Alignment {
        sizeClass == .hero ? .bottomLeading : .bottomLeading
    }

    private var showsBadge: Bool {
        switch sizeClass {
        case .tiny: return false
        case .card, .hero: return true
        }
    }

    private var displayImage: UIImage? {
        UserGarmentPhotoStore.loadThumbnail(imagePath: garment.imagePath,
            maxPixel: sizeClass == .hero ? 1600 : max(64, Int(height * 3)))
    }

    private var isUserPhoto: Bool {
        displayImage != nil
    }

    private var badge: some View {
        Text(isUserPhoto ? "PHOTO" : "FIXTURE")
            .font(sizeClass == .hero ? .caption2.weight(.bold) : .caption2.weight(.semibold))
            .padding(.horizontal, sizeClass == .card ? 6 : 8)
            .padding(.vertical, 3)
            .background(.black.opacity(0.55), in: Capsule())
            .foregroundStyle(.white)
            .accessibilityHidden(true)
    }

    private var accessibilityLabel: String {
        if isUserPhoto {
            return "Photo of \(garment.displayName)"
        }
        return "Fixture image for \(garment.displayName)"
    }

    private var swatchColor: Color {
        let hex = ColorFamilyCatalog.resolvedHex(
            family: garment.colorPrimary?.family,
            name: garment.colorPrimary?.name,
            hex: garment.colorPrimary?.hex
        )
        if let hex, let color = Color(hex: hex) { return color }
        return .blue
    }
}

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return nil }
        self.init(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }
}

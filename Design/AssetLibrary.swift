import SwiftUI

/// Single entry point to the design asset library: semantic colours, slot silhouettes,
/// onboarding illustrations (all in `Assets.xcassets`) and the SF Symbols the app uses.
///
/// Naming rule: catalog names look like `group.camelCase`.
/// Every catalog name referenced here must exist, and every catalog asset must be
/// referenced here — `scripts/check-asset-library.py` enforces both directions.
enum AssetLibrary {

    // MARK: - Colours

    /// Semantic colours. Light and dark variants live in the catalog, never in code.
    enum Palette {
        // Availability (glyph + colour, never colour alone)
        static let availabilityAvailable = Color("availability.available")
        static let availabilityLaundry = Color("availability.laundry")
        static let availabilityPacked = Color("availability.packed")
        static let availabilityRetired = Color("availability.retired")
        static let availabilityCleaners = Color("availability.cleaners")
        static let availabilityStored = Color("availability.stored")

        // Status
        static let statusDraft = Color("status.draft")
        static let statusGap = Color("status.gap")
        static let statusSuccess = Color("status.success")
        static let statusFailure = Color("status.failure")
        static let statusOffline = Color("status.offline")
        static let statusInfo = Color("status.info")

        // Surfaces (tints laid over the system background)
        static let surfaceCard = Color("surface.card")
        static let surfaceCardDraft = Color("surface.cardDraft")
        static let surfaceBadge = Color("surface.badge")
        static let surfaceBannerInfo = Color("surface.bannerInfo")
        static let surfaceBannerWarn = Color("surface.bannerWarn")
        static let surfaceBannerError = Color("surface.bannerError")

        // Brand
        static let brandAccent = Color("brand.accent")

        /// Same mapping as `AvailabilityToken.color`, sourced from the catalog.
        static func availability(_ token: AvailabilityToken) -> Color {
            switch token {
            case .available: return availabilityAvailable
            case .laundry: return availabilityLaundry
            case .packed: return availabilityPacked
            case .retired: return availabilityRetired
            case .cleaners: return availabilityCleaners
            case .stored: return availabilityStored
            }
        }
    }

    // MARK: - Silhouettes

    /// One template glyph per slot. Tint with `.foregroundStyle`; never show colour alone.
    enum Silhouette {
        static let top = Image("silhouette.top")
        static let midLayer = Image("silhouette.midLayer")
        static let jacket = Image("silhouette.jacket")
        static let outerwear = Image("silhouette.outerwear")
        static let bottom = Image("silhouette.bottom")
        static let footwear = Image("silhouette.footwear")
        static let accessory = Image("silhouette.accessory")
        /// Generic garment placeholder (hanger) for drafts without a photo and empty tiles.
        static let garment = Image("silhouette.garment")

        static func slot(_ slot: StubSlot) -> Image {
            switch slot {
            case .top: return top
            case .midLayer: return midLayer
            case .jacket: return jacket
            case .outerwear: return outerwear
            case .bottom: return bottom
            case .footwear: return footwear
            case .accessory: return accessory
            }
        }
    }

    // MARK: - Illustrations

    /// Line-art template illustrations for onboarding and empty states
    enum Illustration {
        static let captureHang = Image("illustration.captureHang")
        static let capturePlainBackground = Image("illustration.capturePlainBackground")
        static let captureDaylight = Image("illustration.captureDaylight")
        static let emptyWardrobe = Image("illustration.emptyWardrobe")
    }

    // MARK: - SF Symbols

    /// The SF Symbol vocabulary of the app. Use these names instead of string literals so
    /// the same action looks the same on every screen.
    enum Symbol {
        // Navigation and chrome
        static let add = "plus"
        static let addCircle = "plus.circle"
        static let profile = "person.crop.circle"
        static let profileUnconfirmed = "person.crop.circle.badge.clock"
        static let profileMissing = "person.crop.circle.badge.questionmark"
        static let filter = "line.3.horizontal.decrease.circle"
        static let more = "ellipsis.circle"
        static let close = "xmark"
        static let disclosure = "chevron.down"
        static let settings = "gearshape"
        static let diagnostics = "ladybug"

        // Garments and wardrobe
        static let garment = "tshirt"
        static let garmentFilled = "tshirt.fill"
        static let hanger = "hanger"
        static let outfit = "square.stack.3d.up"
        static let camera = "camera"
        static let photoLibrary = "photo.on.rectangle"
        static let photoBatch = "photo.stack"
        static let link = "link"

        // Availability
        static let available = "checkmark.circle.fill"
        static let laundry = "washer.fill"
        static let packed = "suitcase.fill"
        static let retired = "archivebox.fill"
        static let cleaners = "hanger"
        static let stored = "snowflake"

        // Board actions
        static let swap = "arrow.triangle.2.circlepath"
        static let keep = "lock"
        static let kept = "lock.fill"
        static let unlock = "lock.open"
        static let undo = "arrow.uturn.backward"
        static let suggest = "sparkles"

        // Context bar
        static let occasion = "briefcase"
        static let temperature = "thermometer"
        static let rain = "cloud.rain.fill"
        static let noRain = "sun.max"

        // Feedback and status
        static let success = "checkmark.seal.fill"
        static let check = "checkmark"
        static let info = "info.circle"
        static let warning = "exclamationmark.triangle"
        static let attention = "exclamationmark.circle.fill"
        static let offline = "wifi.slash"
        static let empty = "tray"
        static let draft = "pencil.circle"
        static let privacy = "lock.shield"
    }
}

// MARK: - Xcode canvas preview

/// Renders the whole library so Design and iOS can review it in the Xcode canvas
/// (light and dark). Not used by any product screen.
struct AssetLibraryPreview: View {
    private let colors: [(String, Color)] = [
        ("availability.available", AssetLibrary.Palette.availabilityAvailable),
        ("availability.laundry", AssetLibrary.Palette.availabilityLaundry),
        ("availability.packed", AssetLibrary.Palette.availabilityPacked),
        ("availability.retired", AssetLibrary.Palette.availabilityRetired),
        ("availability.cleaners", AssetLibrary.Palette.availabilityCleaners),
        ("availability.stored", AssetLibrary.Palette.availabilityStored),
        ("status.draft", AssetLibrary.Palette.statusDraft),
        ("status.gap", AssetLibrary.Palette.statusGap),
        ("status.success", AssetLibrary.Palette.statusSuccess),
        ("status.failure", AssetLibrary.Palette.statusFailure),
        ("status.offline", AssetLibrary.Palette.statusOffline),
        ("status.info", AssetLibrary.Palette.statusInfo),
        ("surface.card", AssetLibrary.Palette.surfaceCard),
        ("surface.cardDraft", AssetLibrary.Palette.surfaceCardDraft),
        ("surface.badge", AssetLibrary.Palette.surfaceBadge),
        ("surface.bannerInfo", AssetLibrary.Palette.surfaceBannerInfo),
        ("surface.bannerWarn", AssetLibrary.Palette.surfaceBannerWarn),
        ("surface.bannerError", AssetLibrary.Palette.surfaceBannerError),
        ("brand.accent", AssetLibrary.Palette.brandAccent),
    ]

    private let silhouettes: [(String, Image)] = [
        ("Top", AssetLibrary.Silhouette.top),
        ("Mid layer", AssetLibrary.Silhouette.midLayer),
        ("Jacket", AssetLibrary.Silhouette.jacket),
        ("Outerwear", AssetLibrary.Silhouette.outerwear),
        ("Bottom", AssetLibrary.Silhouette.bottom),
        ("Footwear", AssetLibrary.Silhouette.footwear),
        ("Accessory", AssetLibrary.Silhouette.accessory),
        ("Garment", AssetLibrary.Silhouette.garment),
    ]

    private let illustrations: [(String, Image)] = [
        ("Hang it", AssetLibrary.Illustration.captureHang),
        ("Plain background", AssetLibrary.Illustration.capturePlainBackground),
        ("Daylight", AssetLibrary.Illustration.captureDaylight),
        ("Empty wardrobe", AssetLibrary.Illustration.emptyWardrobe),
    ]

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Colours").font(.headline)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(colors, id: \.0) { name, color in
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(color)
                                .frame(height: 48)
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.secondary.opacity(0.3)))
                            Text(name).font(.caption2).multilineTextAlignment(.center)
                        }
                    }
                }

                Text("Silhouettes").font(.headline)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(silhouettes, id: \.0) { name, image in
                        VStack(spacing: 6) {
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(width: 48, height: 48)
                                .foregroundStyle(AssetLibrary.Palette.brandAccent)
                            Text(name).font(.caption2)
                        }
                    }
                }

                Text("Illustrations").font(.headline)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(illustrations, id: \.0) { name, image in
                        VStack(spacing: 6) {
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(width: 80, height: 80)
                                .foregroundStyle(.primary)
                            Text(name).font(.caption2)
                        }
                    }
                }

                Text("Availability").font(.headline)
                HStack(spacing: 16) {
                    ForEach(AvailabilityToken.allCases, id: \.self) { token in
                        Label(token.accessibilityName, systemImage: token.symbolName)
                            .font(.caption)
                            .foregroundStyle(AssetLibrary.Palette.availability(token))
                    }
                }
            }
            .padding()
        }
    }
}

#Preview("Asset library · light") {
    AssetLibraryPreview()
}

#Preview("Asset library · dark") {
    AssetLibraryPreview()
        .preferredColorScheme(.dark)
}

import Foundation

/// DEMO display helpers — never show raw enums / machine tokens in UI (demo-ux-polish P2-2).
enum DressingCopy {
    static func formality(_ n: Int?) -> String {
        guard let n else { return "—" }
        switch n {
        case 1: return "Very casual"
        case 2: return "Casual"
        case 3: return "Smart casual"
        case 4: return "Business"
        case 5: return "Formal"
        default: return "Level \(n)"
        }
    }

    static func warmth(_ n: Int?) -> String {
        guard let n else { return "—" }
        switch n {
        case 1: return "Very light"
        case 2: return "Light"
        case 3: return "Medium"
        case 4: return "Warm"
        case 5: return "Very warm"
        default: return "Level \(n)"
        }
    }

    /// Keep names and hyphens intact; normalize legacy engine fragments during rollout.
    static func humanReason(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(
            of: #"better for (cold|cool|mild|warm|hot)(?! weather)\b"#,
            with: "suits $1 weather", options: .regularExpression
        )
        let parts = text.components(separatedBy: ", and ")
        if parts.count > 2 || (parts.count == 2 && !parts[0].contains(", ")) {
            text = parts.count == 2 ? parts.joined(separator: " and ")
                : parts.dropLast().joined(separator: ", ") + ", and " + parts.last!
        }
        guard let first = text.first else { return "Works with the pieces you’re keeping." }
        text = first.uppercased() + text.dropFirst()
        // Legacy servers can return 120 characters without punctuation.
        if text.count > 120 || (text.count == 120 && !text.hasSuffix(".")) {
            let prefix = String(text.prefix(118))
            text = (prefix.lastIndex(of: " ").map { String(prefix[..<$0]) } ?? prefix) + "…"
        }
        if !text.hasSuffix(".") && !text.hasSuffix("…") { text += "." }
        return text
    }

    /// D-20 / #95 — honest copy when Try another cannot produce a different set.
    static let noAlternativeDefault =
        "That’s the only combination your available wardrobe supports for this starting item"

    static func noAlternative(_ engineReason: String?) -> String {
        let trimmed = engineReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty { return noAlternativeDefault }
        return trimmed
    }

    // MARK: - #112 / D-43 generation loading & failure

    static let generateUnreachable = "Can't reach the stylist service."
    static let generateServiceError = "The stylist service returned an error."
    static let generateFailureWithPriorBanner = "Couldn't update — showing your previous outfit."
    static let generateFailureRetryWithOutfit = "Tap Retry to try again."
    static let generateFailureRetryNoOutfit =
        "Retry when the service is back, or pick another starting item."

    static func buildingAround(_ startingItemName: String) -> String {
        "Building around \(startingItemName)…"
    }

    static func tryingAnotherAround(_ startingItemName: String) -> String {
        "Trying another around \(startingItemName)…"
    }

    static func updatingForContext(occasion: DayOccasion, rain: Bool, temperature: TempBand) -> String {
        var parts: [String] = [occasion.rawValue, temperature.rawValue]
        if rain { parts.append("rain") }
        return "Updating for \(parts.joined(separator: " · "))…"
    }

    /// Product copy for generate failures — never surface raw HTTP / URL errors (AC-5).
    static func generateFailureDetail(from error: Error) -> (user: String, diagnostic: String) {
        if let client = error as? OutfitEngineClient.ClientError {
            switch client {
            case .transport:
                return (generateUnreachable, client.errorDescription ?? "transport")
            case .http(let code, _):
                if (500...599).contains(code) || code == 429 {
                    return (generateServiceError, client.errorDescription ?? "http \(code)")
                }
                return (generateServiceError, client.errorDescription ?? "http \(code)")
            case .problem(let p):
                let code = p.code ?? ""
                if code == "GARMENT_NOT_READY" || code.uppercased().contains("COVERAGE") {
                    return ("Add more ready pieces to build an outfit.", client.errorDescription ?? code)
                }
                return (generateServiceError, client.errorDescription ?? code)
            case .anchorNotInWardrobe:
                return ("This starting item isn't ready to send yet.", client.errorDescription ?? "anchor")
            case .missingDeviceToken:
                return ("This build isn't signed in to the remote stylist yet.", client.errorDescription ?? "missing device token")
            case .unauthorized:
                return (deviceAccessRejectedTitle, client.errorDescription ?? "unauthorized")
            case .badURL, .decode:
                return (generateServiceError, client.errorDescription ?? "engine")
            }
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return (generateUnreachable, error.localizedDescription)
        }
        return (generateServiceError, error.localizedDescription)
    }

    /// Relative last-worn line — never raw ISO. App history has no intake suffix.
    static func lastWornLine(appDate: Date?, fixtureISO: String?, now: Date = Date()) -> String? {
        if let appDate {
            return "Last worn \(relativeDay(appDate, now: now))"
        }
        if let fixtureISO, let day = WearLogging.parseISODay(fixtureISO) {
            return "Last worn \(relativeDay(day, now: now)), from intake"
        }
        return nil
    }

    // MARK: - #109 swap sheet empty states (OpenAPI `emptyReason`)

    struct SwapEmptyState: Sendable {
        var title: String
        var message: String
        var systemImage: String
    }

    static func swapEmptyState(code: String?) -> SwapEmptyState {
        switch code {
        case "SET_BLOCKED":
            return SwapEmptyState(
                title: "Can’t swap this piece",
                message: "Every option needs its matching piece, and that piece can’t join this outfit.",
                systemImage: "link"
            )
        case "NO_ELIGIBLE":
            return SwapEmptyState(
                title: "Nothing to swap in",
                message: "Nothing available and ready for this slot right now.",
                systemImage: "tshirt"
            )
        case "COMBINATION_BLOCKED":
            return SwapEmptyState(
                title: "No good matches",
                message: "Nothing left that works with the pieces you’re keeping.",
                systemImage: "exclamationmark.triangle"
            )
        case "LOCK_FIXED":
            return SwapEmptyState(
                title: "This piece stays",
                message: "This piece stays — it’s your starting item or you kept it.",
                systemImage: "lock.fill"
            )
        default:
            return SwapEmptyState(
                title: "No alternatives",
                message: "No ranked swaps for this slot.",
                systemImage: "tray"
            )
        }
    }

    static let swapOfflineMessage = "You’re offline — swap isn’t available."

    // MARK: - #89 / D-46 device access (Release enroll)

    static let deviceAccessReady = "Device access: ready"
    static let deviceAccessNotSetUp = "Device access: not set up"
    static let deviceAccessPasteSuccess = "Device access saved"
    static let deviceAccessPasteEmpty = "Paste a device token first"
    static let deviceAccessEnrollSuccess = "Device access set up"
    static let deviceAccessEnrollFailure = "Couldn’t set up device access. Check the secret and try again."
    static let deviceAccessEnrollEmpty = "Enter the enrollment secret first"
    static let deviceAccessCleared = "Device access cleared"

    static let deviceAccessRejectedTitle = "This phone isn't authorized"
    static let deviceAccessRejectedNoOutfit =
        "New outfits can't load until device access is set up again. Your wardrobe is safe on this phone."
    static let deviceAccessRejectedWithOutfit =
        "Showing your previous outfit. New outfits and swaps can't load until device access is set up again."
    static let deviceAccessRejectedSwap =
        "Swaps can't load until device access is set up again. Your outfit hasn't changed."
    static let deviceAccessSetUpAction = "Set up device access"
    static let deviceAccessRequiredHint = "Set up device access first."
    static let deviceAccessNotAccepted = "Device access: not accepted"
    static let deviceAccessNotAcceptedHelp =
        "This phone's access wasn't accepted. Enroll again with your enrollment secret."
    static let deviceAccessAskOwner = "If you didn't set up this app, ask the person who did."
    static let deviceAccessModeHelpSecret =
        "Use this to set up a phone. The app gets its own access from it."
    static let deviceAccessModeHelpToken =
        "Only for access this app already issued. Most people should use Enrollment secret."
    static let deviceAccessWrongShape =
        "That doesn't look like a device token. If it's an enrollment secret, choose Enrollment secret and paste it there."
    static let deviceAccessEnrollSuccessAnnouncement = "Device access set up. New outfits can load again."
    static let deviceAccessSetUpActionHint = "Opens Device access in Style profile."

    /// Set partner line for swap rows (#109 AC-3).
    static func swapSetPartnerLines(partnerGarments: [StubGarment]) -> [String] {
        partnerGarments.map { g in
            "Also brings \(g.displayName) (\(g.slot.displayLabel))."
        }
    }

    static func relativeDay(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now)
        ).day ?? 0
        switch days {
        case 0: return "today"
        case 1: return "yesterday"
        case 2...13: return "\(days) days ago"
        default:
            if days < 45 {
                let weeks = max(2, days / 7)
                return "about \(weeks) weeks ago"
            }
            let f = DateFormatter()
            f.locale = .current
            f.setLocalizedDateFormatFromTemplate("MMMd")
            return f.string(from: date)
        }
    }
}

enum DayOccasion: String, CaseIterable, Identifiable {
    case workStandard = "Work"
    case workImportant = "Work — important"
    case casualDay = "Casual day"
    case eveningOut = "Evening out"
    case weekendErrands = "Weekend"
    case specialEvent = "Special event"

    var id: String { rawValue }

    /// openapi Occasion enum
    var apiValue: String {
        switch self {
        case .workStandard: return "WORK_STANDARD"
        case .workImportant: return "WORK_IMPORTANT"
        case .casualDay: return "CASUAL_DAY"
        case .eveningOut: return "EVENING_OUT"
        case .weekendErrands: return "WEEKEND_ERRANDS"
        case .specialEvent: return "SPECIAL_EVENT"
        }
    }

    var occasionFormality: Int {
        switch self {
        case .casualDay, .weekendErrands: return 2
        case .workStandard: return 3
        case .eveningOut: return 4
        case .workImportant, .specialEvent: return 5
        }
    }
}

enum TempBand: String, CaseIterable, Identifiable {
    case cold = "Cold"
    case cool = "Cool"
    case mild = "Mild"
    case warm = "Warm"
    case hot = "Hot"

    var id: String { rawValue }

    /// openapi TemperatureBand enum
    var apiValue: String { rawValue.uppercased() }
}

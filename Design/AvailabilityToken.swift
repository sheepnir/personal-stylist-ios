import SwiftUI

/// Availability chrome (PRD §13.5: symbol + colour, never colour alone).
enum AvailabilityToken: String, CaseIterable, Sendable {
    case available = "AVAILABLE"
    case laundry = "LAUNDRY"
    case packed = "PACKED"
    case retired = "RETIRED"
    case cleaners = "CLEANERS"
    case stored = "STORED"

    init(raw: String) {
        self = AvailabilityToken(rawValue: raw.uppercased()) ?? .available
    }

    var symbolName: String {
        switch self {
        case .available: return "checkmark.circle.fill"
        case .laundry: return "washer.fill"
        case .packed: return "suitcase.fill"
        case .retired: return "archivebox.fill"
        case .cleaners: return "hanger"
        case .stored: return "snowflake"
        }
    }

    var color: Color {
        switch self {
        case .available: return .green
        case .laundry: return .orange
        case .packed: return .indigo
        case .retired: return .secondary
        case .cleaners: return .teal
        case .stored: return .cyan
        }
    }

    var accessibilityName: String {
        switch self {
        case .available: return "Available"
        case .laundry: return "In laundry"
        case .packed: return "Packed"
        case .retired: return "Retired"
        case .cleaners: return "At cleaners"
        case .stored: return "Stored"
        }
    }
}

struct AvailabilityBadge: View {
    let token: AvailabilityToken

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: token.symbolName)
                .foregroundStyle(token.color)
            Text(token.accessibilityName)
                .foregroundStyle(token == .retired ? Color.primary : token.color)
        }
        .font(.caption.weight(.semibold))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(token.accessibilityName)
    }
}

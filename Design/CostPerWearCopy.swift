import Foundation

/// D-21 four total-count prior-wear buckets (skippable). Midpoints are config, never shown raw.
enum PriorWearBucket: String, CaseIterable, Identifiable, Sendable {
    case under5 = "UNDER_5"
    case from5To20 = "FROM_5_TO_20"
    case from20To50 = "FROM_20_TO_50"
    case over50 = "OVER_50"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .under5: return "Barely — fewer than 5 times"
        case .from5To20: return "A fair bit — 5 to 20 times"
        case .from20To50: return "A lot — 20 to 50 times"
        case .over50: return "Constantly — more than 50"
        }
    }

    var midpoint: Int {
        switch self {
        case .under5: return 3
        case .from5To20: return 12
        case .from20To50: return 35
        case .over50: return 75
        }
    }
}

/// PRD §7.8 display states — client-composed (D-19). Unknown price is never "$0".
enum CostPerWearCopy {
    struct Summary: Equatable, Sendable {
        var wearLine: String
        var cpwLine: String
        var accessibilityLabel: String
        var hasPrice: Bool
        var addPriceTitle: String
    }

    static var deviceCurrency: String {
        Locale.current.currency?.identifier ?? AppIdentity.defaultCurrency
    }

    static func summary(
        price: Decimal?,
        currency: String?,
        confirmedWears: Int,
        priorWearBucket: String?,
        priorWearEstimate: Int?
    ) -> Summary {
        let code = (currency?.isEmpty == false ? currency! : deviceCurrency)
        let prior = resolvedPriorEstimate(bucket: priorWearBucket, estimate: priorWearEstimate)
        let wearLine: String
        if confirmedWears > 0 {
            wearLine = "\(confirmedWears) wear\(confirmedWears == 1 ? "" : "s") in the app"
        } else if prior != nil {
            wearLine = "Not yet worn since you started"
        } else {
            wearLine = "Not worn yet"
        }

        guard let price, price > 0 else {
            let cpw = "No price recorded"
            return Summary(
                wearLine: wearLine,
                cpwLine: cpw,
                accessibilityLabel: "\(wearLine). \(cpw)",
                hasPrice: false,
                addPriceTitle: "Add price"
            )
        }

        let money: (Decimal) -> String = { formatMoney($0, currencyCode: code) }

        let cpw: String
        if let prior {
            let lifetime = prior + max(0, confirmedWears)
            let perWear = price / Decimal(lifetime)
            if confirmedWears == 0 {
                cpw = "\(money(perWear)) per wear (estimated) · not yet worn since you started"
            } else {
                cpw = "\(money(perWear)) per wear (estimated lifetime, \(lifetime) wears) · \(confirmedWears) confirmed in the app"
            }
        } else if confirmedWears == 0 {
            cpw = "Wearing this once brings it to \(money(price))"
        } else {
            let perWear = price / Decimal(confirmedWears)
            cpw = "\(money(perWear)) per wear · \(confirmedWears) wear\(confirmedWears == 1 ? "" : "s") in the app"
        }

        return Summary(
            wearLine: wearLine,
            cpwLine: cpw,
            accessibilityLabel: "\(wearLine). \(cpw)",
            hasPrice: true,
            addPriceTitle: "Edit price"
        )
    }

    static func summary(for garment: StubGarment, confirmedWears: Int) -> Summary {
        summary(
            price: garment.purchasePrice,
            currency: garment.purchaseCurrency,
            confirmedWears: confirmedWears,
            priorWearBucket: garment.priorWearBucket,
            priorWearEstimate: garment.priorWearEstimate
        )
    }

    static func successLine(for garment: StubGarment, confirmedWears: Int) -> String? {
        let s = summary(for: garment, confirmedWears: confirmedWears)
        return s.hasPrice ? s.cpwLine : nil
    }

    /// #127 wear-success line — one representative priced piece (largest CPW movement, else first priced).
    struct WearSuccessPresentation: Equatable, Sendable {
        var pricedLine: String?
        /// When no worn piece has a price, navigate to Add price / detail for this garment.
        var addPricesGarmentId: UUID?
    }

    static func wearSuccessPresentation(
        wornGarments: [StubGarment],
        wearCount: (UUID) -> Int
    ) -> WearSuccessPresentation {
        guard !wornGarments.isEmpty else {
            return WearSuccessPresentation(pricedLine: nil, addPricesGarmentId: nil)
        }

        var best: (garment: StubGarment, movement: Decimal)?
        for g in wornGarments {
            guard let price = g.purchasePrice, price > 0 else { continue }
            let confirmed = wearCount(g.id)
            guard confirmed > 0 else { continue }
            let prior = resolvedPriorEstimate(bucket: g.priorWearBucket, estimate: g.priorWearEstimate)
            let newPer = perWearDecimal(price: price, confirmedWears: confirmed, priorEstimate: prior)
            let oldPer: Decimal
            if confirmed <= 1 {
                if let prior, prior > 0 {
                    oldPer = price / Decimal(prior)
                } else {
                    oldPer = price
                }
            } else {
                oldPer = perWearDecimal(price: price, confirmedWears: confirmed - 1, priorEstimate: prior)
            }
            let movement = abs(oldPer - newPer)
            if best == nil || movement > best!.movement {
                best = (g, movement)
            }
        }

        if let g = best?.garment ?? wornGarments.first(where: { ($0.purchasePrice ?? 0) > 0 }) {
            let confirmed = wearCount(g.id)
            let code = (g.purchaseCurrency?.isEmpty == false ? g.purchaseCurrency! : deviceCurrency)
            let prior = resolvedPriorEstimate(bucket: g.priorWearBucket, estimate: g.priorWearEstimate)
            let per = perWearDecimal(price: g.purchasePrice!, confirmedWears: max(1, confirmed), priorEstimate: prior)
            let line = "\(g.displayName) is now \(formatMoney(per, currencyCode: code)) per wear"
            return WearSuccessPresentation(pricedLine: line, addPricesGarmentId: nil)
        }

        return WearSuccessPresentation(pricedLine: nil, addPricesGarmentId: wornGarments.first?.id)
    }

    private static func perWearDecimal(price: Decimal, confirmedWears: Int, priorEstimate: Int?) -> Decimal {
        if let priorEstimate, priorEstimate > 0 {
            let lifetime = priorEstimate + max(0, confirmedWears)
            return price / Decimal(max(1, lifetime))
        }
        return price / Decimal(max(1, confirmedWears))
    }

    static func formatMoney(_ amount: Decimal, currencyCode: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        let number = NSDecimalNumber(decimal: amount)
        return formatter.string(from: number) ?? "\(currencyCode) \(number)"
    }

    static func parsePrice(_ raw: String) -> Decimal? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let value = Decimal(string: normalized), value > 0 else { return nil }
        return value
    }

    private static func resolvedPriorEstimate(bucket: String?, estimate: Int?) -> Int? {
        if let estimate, estimate > 0 { return estimate }
        if let bucket, let known = PriorWearBucket(rawValue: bucket) { return known.midpoint }
        return nil
    }
}

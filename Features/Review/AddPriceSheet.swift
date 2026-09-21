import SwiftUI

/// DEMO-minimal price entry (PRD §7.2 optional extras / §7.8 / D-21). No favourite / wardrobe CPW screen.
struct AddPriceSheet: View {
    @ObservedObject var model: LoopDemoModel
    let garmentId: UUID
    var onSaved: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var priceText = ""
    @State private var currency = CostPerWearCopy.deviceCurrency
    @State private var includePurchaseDate = false
    @State private var purchaseDate = Date()
    @State private var priorWearBucket = ""
    @State private var isSaving = false
    @State private var errorText: String?

    private var garment: StubGarment? {
        model.garments.first(where: { $0.id == garmentId })
    }

    var body: some View {
        NavigationStack {
            Form {
                if let g = garment {
                    Section {
                        Text(g.displayName)
                            .font(.headline)
                        Text("Price is optional. Leave it blank if you don’t know — never stored as $0.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Section {
                        GarmentPriceAmountFields(priceText: $priceText, currency: $currency)
                    } header: {
                        Text("Price")
                    } footer: {
                        Text("Device default is \(CostPerWearCopy.deviceCurrency). Blank is “No price recorded”, never $0.")
                    }

                    Section {
                        GarmentPriceOptionalFields(
                            includePurchaseDate: $includePurchaseDate,
                            purchaseDate: $purchaseDate,
                            priorWearBucket: $priorWearBucket
                        )
                    } header: {
                        Text("Optional")
                    } footer: {
                        Text("Skippable. Counts are estimated totals (D-21), not how often you wear it.")
                    }
                    if let errorText {
                        Section {
                            Text(errorText)
                                .foregroundStyle(.red)
                                .font(.footnote)
                        }
                    }
                } else {
                    ContentUnavailableView("Garment missing", systemImage: "tshirt")
                }
            }
            .navigationTitle(garment?.purchasePrice == nil ? "Add price" : "Edit price")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving || garment == nil)
                        .fontWeight(.semibold)
                }
            }
            .onAppear { seedFromGarment() }
        }
    }

    private func seedFromGarment() {
        guard let g = garment else { return }
        if let price = g.purchasePrice, price > 0 {
            priceText = NSDecimalNumber(decimal: price).stringValue
        }
        currency = g.purchaseCurrency ?? CostPerWearCopy.deviceCurrency
        if let date = g.purchaseDate {
            includePurchaseDate = true
            purchaseDate = date
        }
        priorWearBucket = g.priorWearBucket ?? ""
    }

    @MainActor
    private func save() async {
        guard let g = garment else { return }
        isSaving = true
        errorText = nil
        defer { isSaving = false }

        let price = CostPerWearCopy.parsePrice(priceText)
        if !priceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, price == nil {
            errorText = "Enter a price greater than 0, or leave it blank."
            return
        }

        let ok = await model.savePurchaseInfo(
            id: g.id,
            price: price,
            currency: price == nil ? nil : currency,
            purchaseDate: includePurchaseDate ? purchaseDate : nil,
            priorWearBucket: priorWearBucket.isEmpty ? nil : priorWearBucket
        )
        if ok {
            onSaved()
            dismiss()
        } else {
            errorText = "Couldn’t save price — try again."
        }
    }
}

struct GarmentPriceAmountFields: View {
    @Binding var priceText: String
    @Binding var currency: String

    private var currencyOptions: [String] {
        var codes = [CostPerWearCopy.deviceCurrency, "USD", "EUR", "GBP", "ILS", "CAD", "AUD"]
        if !codes.contains(currency) { codes.insert(currency, at: 0) }
        var seen = Set<String>()
        return codes.filter { seen.insert($0).inserted }
    }

    var body: some View {
        TextField("Amount", text: $priceText)
            .keyboardType(.decimalPad)
            .accessibilityLabel("Purchase price")
        Picker("Currency", selection: $currency) {
            ForEach(currencyOptions, id: \.self) { Text($0).tag($0) }
        }
    }
}

struct GarmentPriceOptionalFields: View {
    @Binding var includePurchaseDate: Bool
    @Binding var purchaseDate: Date
    @Binding var priorWearBucket: String

    var body: some View {
        Toggle("Purchase date", isOn: $includePurchaseDate)
        if includePurchaseDate {
            DatePicker(
                "Purchased",
                selection: $purchaseDate,
                displayedComponents: .date
            )
        }
        Picker("Prior wears", selection: $priorWearBucket) {
            Text("Skip").tag("")
            ForEach(PriorWearBucket.allCases) { bucket in
                Text(bucket.label).tag(bucket.rawValue)
            }
        }
    }
}

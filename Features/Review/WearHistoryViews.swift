import SwiftUI

/// Last five non-voided wears + See all. Void uses in-app confirm (D-72).
struct WearHistorySection: View {
    @ObservedObject var model: LoopDemoModel
    let garmentId: UUID

    @State private var wearToVoid: StubWearEvent?

    private var recent: [StubWearEvent] {
        model.recentWearHistory(for: garmentId)
    }

    private var all: [StubWearEvent] {
        model.wearHistoryAll(for: garmentId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(WearHistoryCopy.sectionTitle)
                .font(.headline)
            if recent.isEmpty {
                Text(WearHistoryCopy.empty)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .accessibilityLabel(WearHistoryCopy.empty)
            } else {
                ForEach(recent) { event in
                    WearHistoryRow(
                        event: event,
                        outfitName: outfitName(for: event),
                        showsVoidAction: true
                    ) {
                        wearToVoid = event
                    }
                }
            }
            if !all.isEmpty {
                NavigationLink {
                    WearHistoryListView(model: model, garmentId: garmentId)
                } label: {
                    Text(WearHistoryCopy.seeAll)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .accessibilityLabel(WearHistoryCopy.seeAllAccessibility)
                .accessibilityHint(WearHistoryCopy.seeAllHint)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        .wearVoidConfirmation(wearToVoid: $wearToVoid, model: model)
    }

    private func outfitName(for event: StubWearEvent) -> String? {
        WearHistoryCopy.resolvedOutfitName(
            sourceOutfitId: event.sourceOutfitId,
            currentOutfit: model.outfit,
            wornGarmentIds: event.garmentIds,
            garments: model.garments
        )
    }
}

/// Full history including voided rows (not voidable again).
struct WearHistoryListView: View {
    @ObservedObject var model: LoopDemoModel
    let garmentId: UUID

    @State private var wearToVoid: StubWearEvent?

    private var events: [StubWearEvent] {
        model.wearHistoryAll(for: garmentId)
    }

    var body: some View {
        List {
            if events.isEmpty {
                Text(WearHistoryCopy.empty)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .accessibilityLabel(WearHistoryCopy.empty)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(events) { event in
                    WearHistoryRow(
                        event: event,
                        outfitName: outfitName(for: event),
                        showsVoidAction: !event.isVoided
                    ) {
                        wearToVoid = event
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }
        }
        .navigationTitle(WearHistoryCopy.sectionTitle)
        .navigationBarTitleDisplayMode(.inline)
        .wearVoidConfirmation(wearToVoid: $wearToVoid, model: model)
    }

    private func outfitName(for event: StubWearEvent) -> String? {
        WearHistoryCopy.resolvedOutfitName(
            sourceOutfitId: event.sourceOutfitId,
            currentOutfit: model.outfit,
            wornGarmentIds: event.garmentIds,
            garments: model.garments
        )
    }
}

private struct WearHistoryRow: View {
    let event: StubWearEvent
    let outfitName: String?
    var showsVoidAction: Bool
    var onVoid: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(WearHistoryCopy.rowLine(wornOn: event.wornOn, outfitName: outfitName))
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(
                    WearHistoryCopy.rowAccessibility(
                        wornOn: event.wornOn,
                        outfitName: outfitName,
                        isVoided: event.isVoided
                    )
                )
            if event.isVoided {
                Text(WearHistoryCopy.voidedLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            } else if showsVoidAction {
                Button(WearHistoryCopy.voidAction, role: .destructive, action: onVoid)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel(WearHistoryCopy.voidAction)
                    .accessibilityHint(WearHistoryCopy.voidHint)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
}

private extension View {
    func wearVoidConfirmation(
        wearToVoid: Binding<StubWearEvent?>,
        model: LoopDemoModel
    ) -> some View {
        confirmationDialog(
            WearHistoryCopy.voidTitle,
            isPresented: Binding(
                get: { wearToVoid.wrappedValue != nil },
                set: { if !$0 { wearToVoid.wrappedValue = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(WearHistoryCopy.voidConfirm, role: .destructive) {
                if let id = wearToVoid.wrappedValue?.id {
                    Task { await model.voidWear(id: id) }
                }
                wearToVoid.wrappedValue = nil
            }
            .accessibilityLabel(WearHistoryCopy.voidConfirm)
            Button(WearHistoryCopy.cancel, role: .cancel) {
                wearToVoid.wrappedValue = nil
            }
            .accessibilityLabel(WearHistoryCopy.cancel)
        } message: {
            Text(WearHistoryCopy.voidMessage)
        }
    }
}

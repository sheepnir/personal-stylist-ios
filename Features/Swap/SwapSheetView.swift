import SwiftUI

/// #109 / P2-3 — swap compare with current piece, Suggest for me, named set partners, emptyReason actions.
struct SwapSheetView: View {
    @ObservedObject var model: LoopDemoModel
    var onClose: () -> Void
    var onChangeStartingItem: () -> Void = {}
    var onOpenWardrobe: () -> Void = {}

    var body: some View {
        NavigationStack {
            Group {
                if model.isOffline {
                    swapEmptyView(
                        title: "Swap unavailable",
                        systemImage: "wifi.slash",
                        message: DressingCopy.swapOfflineMessage,
                        actions: { Button("Close", action: onClose).buttonStyle(.borderedProminent) }
                    )
                } else if model.isLoadingAlternatives {
                    ProgressView("Finding alternatives…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.swapAlternatives.isEmpty {
                    emptyAlternativesView
                } else {
                    alternativesList
                }
            }
            .navigationTitle(model.swapSlot.map { "Swap your \($0.displayLabel)" } ?? "Swap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                }
            }
        }
    }

    private var alternativesList: some View {
        List {
            Section {
                currentPieceHeader
            }
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Section {
                Button {
                    model.applyTopSwapSuggestion()
                    onClose()
                } label: {
                    Label("Suggest for me", systemImage: "sparkles")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 12, trailing: 16))
                .accessibilityHint("Applies the top-ranked swap")
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Section {
                ForEach(model.swapAlternatives) { alt in
                    swapRow(alt)
                }
            }
        }
        .listStyle(.plain)
    }

    private var currentPieceHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let assignment = model.swapSlotAssignment() {
                if assignment.hasGap, let reason = assignment.gapReason {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Currently empty")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("— \(reason)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if let g = model.garment(in: assignment) {
                    HStack(alignment: .top, spacing: 12) {
                        FixtureImageView(garment: g, height: 48, presentation: .tiny)
                            .frame(width: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Currently: \(g.displayName)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(assignment.slot.displayLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("Currently empty")
                        .font(.subheadline.weight(.semibold))
                }
            }
            swapContextChips
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var swapContextChips: some View {
        HStack(spacing: 6) {
            swapContextChip(model.occasion.rawValue, systemImage: "briefcase")
            swapContextChip(model.temperatureBand.rawValue, systemImage: "thermometer")
            swapContextChip(
                model.rain ? "Rain" : "No rain",
                systemImage: model.rain ? "cloud.rain.fill" : "sun.max"
            )
        }
        .accessibilityLabel("Outfit context: \(model.occasion.rawValue), \(model.temperatureBand.rawValue), \(model.rain ? "rain" : "no rain")")
    }

    private func swapContextChip(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
            .foregroundStyle(.primary)
    }

    private func swapRow(_ alt: StubSwapAlternative) -> some View {
        let partners = alt.setPartnerIds.compactMap { id in model.garments.first(where: { $0.id == id }) }
        let partnerLines = DressingCopy.swapSetPartnerLines(partnerGarments: partners)
        let reason = DressingCopy.humanReason(alt.reason)
        let partnerA11y = partnerLines.joined(separator: " ")

        return Button {
            model.applySwap(alt)
            onClose()
        } label: {
            HStack(alignment: .top, spacing: 14) {
                FixtureImageView(garment: alt.garment, height: 72, presentation: .tiny)
                    .frame(width: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 6) {
                    Text(alt.garment.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(reason)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(partnerLines, id: \.self) { line in
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    AvailabilityBadge(token: alt.garment.availabilityToken)
                }
            }
            .padding(.vertical, 4)
        }
        .accessibilityLabel(
            "\(alt.garment.displayName), \(reason)\(partnerA11y.isEmpty ? "" : ". \(partnerA11y)")"
        )
    }

    @ViewBuilder
    private var emptyAlternativesView: some View {
        let state = DressingCopy.swapEmptyState(code: model.swapEmptyReason)
        let detail = model.swapSheetDetail ?? state.message
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                currentPieceHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                swapEmptyView(
                    title: state.title,
                    systemImage: state.systemImage,
                    message: detail,
                    actions: { emptyReasonActions }
                )
            }
        }
    }

    private func swapEmptyView<Actions: View>(
        title: String,
        systemImage: String,
        message: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(spacing: 20) {
            Image(systemName: systemImage)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            actions()
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 24)
    }

    @ViewBuilder
    private var emptyReasonActions: some View {
        switch model.swapEmptyReason {
        case "SET_BLOCKED", "LOCK_FIXED":
            VStack(spacing: 12) {
                if model.swapEmptyReason == "LOCK_FIXED", let slot = model.swapSlot,
                   let a = model.swapSlotAssignment(), a.isLocked, !a.isAnchor {
                    Button("Unlock") {
                        model.setAssignmentLocked(slot: slot, locked: false, assignmentId: a.id)
                        Task { await model.alternatives(for: slot) }
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                Button("Change starting item") {
                    onClose()
                    onChangeStartingItem()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, minHeight: 44)
            }
        case "NO_ELIGIBLE":
            Button("Mark something available") {
                onClose()
                onOpenWardrobe()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity, minHeight: 44)
        case "COMBINATION_BLOCKED":
            VStack(spacing: 12) {
                if let kept = model.outfit?.assignments.first(where: { $0.isLocked && !$0.isAnchor }) {
                    Button("Unlock \(kept.slot.displayLabel)") {
                        model.setAssignmentLocked(slot: kept.slot, locked: false, assignmentId: kept.id)
                        if let slot = model.swapSlot {
                            Task { await model.alternatives(for: slot) }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                Button("Close", action: onClose)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        default:
            Button("Close", action: onClose)
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }
}

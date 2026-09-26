import SwiftUI

/// P1-1 composition-first board — large tiles, Starting item, Swap on tiles.
struct OutfitBoardView: View {
    @ObservedObject var model: LoopDemoModel
    var onSwap: (StubSlot) -> Void
    var onWear: () -> Void
    var onChangeAnchor: () -> Void = {}
    /// D-75 — explicit same-day correction. Must not persist.
    var onChangeWhatIWore: () -> Void = {}
    var onSetUpDeviceAccess: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @AppStorage("demo.boardKeepTipShown") private var boardKeepTipShown = false
    @State private var showKeepTipBanner = false

    /// Main column: non-accessories + accessory Starting item (GH #61).
    private var mainAssignments: [StubOutfitAssignment] {
        guard let outfit = model.outfit else { return [] }
        return outfit.assignments.filter { $0.slot != .accessory || $0.isAnchor }
            .sorted { $0.slot.wearingOrderIndex < $1.slot.wearingOrderIndex }
    }

    /// Accessory strip: non-anchor accessories only (anchor lives in main column).
    private var accessoryAssignments: [StubOutfitAssignment] {
        guard let outfit = model.outfit else { return [] }
        return outfit.assignments.filter {
            $0.slot == .accessory && !$0.isAnchor && ($0.garmentId != nil || $0.gapReason != nil)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                contextBar
                if model.deviceAccessRejected, let fail = model.generateFailureMessage {
                    deviceAccessFailureBanner(fail)
                } else if let fail = model.generateFailureMessage {
                    generateFailureBanner(fail)
                }
                if let reason = model.noAlternativeReason {
                    noAlternativeBanner(reason)
                }
                if model.isGenerating {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(model.generateProgressCopy ?? "Building outfit…")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Button("Cancel") { cancelGenerationTapped() }
                            .buttonStyle(.bordered)
                            .frame(minHeight: 44)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if model.boardUpdatedFlash {
                    Text("Updated")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                        .accessibilityLabel("Outfit updated")
                }
                if model.isOffline {
                    Text(model.outfit?.offlineCached == true
                         ? "You’re offline. Showing the last outfit for this starting item — pieces are still available."
                         : "You’re offline — can’t generate a new outfit right now.")
                        .font(.footnote)
                        .padding(10)
                        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                }
                if let outfit = model.outfit {
                    VStack(spacing: 14) {
                        ForEach(mainAssignments) { a in
                            compositionTile(a)
                        }
                    }
                    if !accessoryAssignments.isEmpty {
                        Text("Accessories")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(accessoryAssignments) { a in
                                    accessoryTile(a)
                                }
                            }
                        }
                    }
                    if !outfit.rationaleSummary.isEmpty {
                        Text(outfit.rationaleSummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if model.isOffline {
                        Text("Try another and swap need a connection.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if showKeepTipBanner {
                        Text("Kept pieces stay when you try another.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                            .accessibilityLabel("Kept pieces stay when you try another.")
                    }
                    if model.wearFlashToken != nil || model.didLogCurrentOutfitToday {
                        Text("Logged as worn")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)
                            .transition(.opacity)
                    }
                } else if model.generateFailureMessage == nil {
                    ContentUnavailableView(
                        "No outfit",
                        systemImage: "square.stack.3d.up",
                        description: Text("Build from the wardrobe first.")
                    )
                }
            }
            .padding()
            .padding(.bottom, 16)
        }
        .safeAreaInset(edge: .bottom) {
            if showsBottomBar {
                bottomBar
            }
        }
        .navigationTitle("Outfit")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if model.outfit == nil, !model.isGenerating, model.generateFailureMessage == nil,
               !model.deviceAccessRejected {
                Task { await model.buildDemoOutfit(intent: .firstBuild) }
            }
        }
        .onDisappear { model.clearWearFlash() }
    }

    private var showsBottomBar: Bool {
        if model.isGenerating { return false }
        if let outfit = model.outfit, !outfit.assignments.contains(where: { $0.isSkeletonPlaceholder }) {
            return true
        }
        return model.generateFailureMessage != nil
    }

    private func cancelGenerationTapped() {
        let firstBuild = model.generateIntent == .firstBuild
        model.cancelGeneration()
        if firstBuild {
            dismiss()
        }
    }

    private var bottomBar: some View {
        Group {
            if model.outfit != nil, !model.outfit!.assignments.contains(where: { $0.isSkeletonPlaceholder }) {
                ViewThatFits(in: .horizontal) {
                    boardPrimaryActions(axis: .horizontal)
                    boardPrimaryActions(axis: .vertical)
                }
            } else if model.generateFailureMessage != nil, model.outfit == nil
                || model.outfit?.assignments.contains(where: { $0.isSkeletonPlaceholder }) == true {
                HStack(spacing: 12) {
                    Button("Change starting item") { onChangeAnchor() }
                        .frame(minHeight: 44)
                        .disabled(model.outfitEngineActionsDisabled)
                        .accessibilityHint(
                            model.outfitEngineActionsDisabled
                                ? DressingCopy.deviceAccessRequiredHint
                                : ""
                        )
                    Spacer()
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private enum BoardBarAxis {
        case horizontal, vertical
    }

    @ViewBuilder
    private func boardPrimaryActions(axis: BoardBarAxis) -> some View {
        let tryAnotherDisabled = model.isOffline || model.isGenerating || model.outfitEngineActionsDisabled
        let primary = model.boardWearPrimary
        let wearDisabled = primary == .changeWhatIWore
            ? model.isGenerating
            : (!model.outfitWearable || model.outfit == nil || model.isGenerating)
        let wearWhy = model.wearDisabledReason()

        switch axis {
        case .horizontal:
            HStack(alignment: .center, spacing: 12) {
                Button("Try another") { Task { await model.tryAnotherOutfit() } }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .disabled(tryAnotherDisabled)
                    .accessibilityHint(
                        model.outfitEngineActionsDisabled
                            ? DressingCopy.deviceAccessRequiredHint
                            : (model.isOffline ? "You’re offline — can’t try another right now." : "")
                    )
                wearPrimaryButtonBlock(
                    alignment: .center,
                    primary: primary,
                    wearDisabled: wearDisabled,
                    wearWhy: wearWhy
                )
                .frame(maxWidth: .infinity)
                boardMoreMenu
            }
        case .vertical:
            VStack(spacing: 10) {
                Button("Try another") { Task { await model.tryAnotherOutfit() } }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .disabled(tryAnotherDisabled)
                    .accessibilityHint(
                        model.outfitEngineActionsDisabled
                            ? DressingCopy.deviceAccessRequiredHint
                            : (model.isOffline ? "You’re offline — can’t try another right now." : "")
                    )
                wearPrimaryButtonBlock(
                    alignment: .center,
                    primary: primary,
                    wearDisabled: wearDisabled,
                    wearWhy: wearWhy
                )
                HStack {
                    Spacer()
                    boardMoreMenu
                }
            }
        }
    }

    private var boardMoreMenu: some View {
        Menu {
            Button("Change starting item") { onChangeAnchor() }
                .disabled(model.isOffline || model.outfitEngineActionsDisabled)
                .accessibilityHint(
                    model.outfitEngineActionsDisabled
                        ? DressingCopy.deviceAccessRequiredHint
                        : ""
                )
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More")
        .accessibilityHint("Change starting item")
    }

    @ViewBuilder
    private func wearPrimaryButtonBlock(
        alignment: HorizontalAlignment,
        primary: DailyWearBoardPrimary,
        wearDisabled: Bool,
        wearWhy: String?
    ) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            DailyWearA11yButton(
                identifier: "dailyWear.boardPrimary",
                label: wearDisabled && wearWhy != nil && primary == .wearingThis
                    ? "\(primary.title), \(wearWhy!)"
                    : primary.title,
                hint: primary.accessibilityHint,
                isEnabled: !wearDisabled,
                action: {
                    if primary == .changeWhatIWore {
                        onChangeWhatIWore()
                        return
                    }
                    Task {
                        await model.wearingThisFromBoard()
                        onWear()
                    }
                }
            ) {
                Text(primary.title)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(
                        (wearDisabled ? Color.accentColor.opacity(0.4) : Color.accentColor),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
            }
            .disabled(wearDisabled)
            .frame(maxWidth: .infinity, minHeight: 44)
            if let why = wearWhy, !model.outfitWearable, primary == .wearingThis {
                Text(why)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(alignment == .trailing ? .trailing : .center)
                    .frame(maxWidth: .infinity, alignment: alignment == .trailing ? .trailing : .center)
            }
        }
    }

    private func boardMiniAction(
        _ title: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(minHeight: 44)
            .disabled(disabled)
    }

    private func keepTapped(slot: StubSlot, assignmentId: UUID) {
        model.setAssignmentLocked(slot: slot, locked: true, assignmentId: assignmentId)
        if !boardKeepTipShown {
            boardKeepTipShown = true
            showKeepTipBanner = true
        }
    }

    private func filledTileLabel(_ a: StubOutfitAssignment, _ g: StubGarment) -> String {
        var parts = [g.displayName]
        if a.isAnchor { parts.append("Starting item") }
        if a.isLocked { parts.append("Kept") }
        parts.append(g.availabilityToken.accessibilityName)
        return parts.joined(separator: ", ")
    }


    private func noAlternativeBanner(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No other combination")
                .font(.subheadline.weight(.semibold))
            Text(reason)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No other combination. \(reason)")
    }

    private func deviceAccessFailureBanner(_ title: String) -> some View {
        let body = model.generateFailureSubtitle ?? DressingCopy.deviceAccessRejectedNoOutfit
        return VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text(body)
                .font(.footnote)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Button(DressingCopy.deviceAccessSetUpAction, action: onSetUpDeviceAccess)
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityHint(DressingCopy.deviceAccessSetUpActionHint)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title). \(body)")
    }

    private func generateFailureBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.subheadline.weight(.semibold))
            if let subtitle = model.generateFailureSubtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if model.outfit != nil {
                Text(DressingCopy.generateFailureRetryWithOutfit)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text(DressingCopy.generateFailureRetryNoOutfit)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button("Retry") {
                Task {
                    let intent: LoopDemoModel.GenerateIntent = {
                        if model.contextDirty { return .updateContext }
                        return model.outfit != nil ? .tryAnother : .firstBuild
                    }()
                    await model.buildDemoOutfit(preserveLocks: true, intent: intent)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isOffline || model.isGenerating)
            .frame(minHeight: 44)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(message)
    }

    private var contextBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(DayOccasion.allCases) { o in
                        Button(o.rawValue) {
                            model.occasion = o
                            model.markContextChanged()
                        }
                    }
                } label: {
                    contextChip(model.occasion.rawValue, systemImage: "briefcase")
                }
                .frame(minHeight: 44)
                .accessibilityLabel("Occasion")
                .accessibilityValue(model.occasion.rawValue)
                .accessibilityHint("Choose occasion for this outfit")

                Menu {
                    ForEach(TempBand.allCases) { t in
                        Button(t.rawValue) {
                            model.temperatureBand = t
                            model.markContextChanged()
                        }
                    }
                } label: {
                    contextChip(model.temperatureBand.rawValue, systemImage: "thermometer")
                }
                .frame(minHeight: 44)
                .accessibilityLabel("Temperature")
                .accessibilityValue(model.temperatureBand.rawValue)
                .accessibilityHint("Choose temperature for this outfit")

                Button {
                    model.rain.toggle()
                    model.markContextChanged()
                } label: {
                    contextChip(model.rain ? "Rain" : "No rain", systemImage: model.rain ? "cloud.rain.fill" : "sun.max")
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .accessibilityLabel("Rain")
                .accessibilityValue(model.rain ? "On" : "Off")
                .accessibilityHint("Turns rain consideration on or off")

                Spacer(minLength: 0)
            }

            if model.contextDirty, !(model.isGenerating && model.generateIntent == .updateContext) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Out of date for this weather/occasion")
                        .font(.subheadline.weight(.semibold))
                    Text("Your outfit still shows the previous context. Update when you’re ready.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Update outfit") {
                        Task { await model.updateOutfitForContext() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isOffline || model.isGenerating || model.outfitEngineActionsDisabled)
                    .frame(minHeight: 44)
                    .accessibilityHint(
                        model.outfitEngineActionsDisabled
                            ? DressingCopy.deviceAccessRequiredHint
                            : ""
                    )
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func contextChip(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
            .foregroundStyle(.primary)
    }

    @ViewBuilder
    private func compositionTile(_ a: StubOutfitAssignment) -> some View {
        if a.isSkeletonPlaceholder {
            skeletonTile(a)
        } else if let gid = a.garmentId, let g = model.garments.first(where: { $0.id == gid }) {
            let unavailable = g.availability != "AVAILABLE"
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    FixtureImageView(garment: g, height: 180, presentation: .card)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .opacity(unavailable && !a.isAnchor ? 0.45 : 1.0)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(a.isAnchor ? Color.accentColor : Color.clear, lineWidth: 3)
                        )
                    if a.isAnchor {
                        Text("Starting item")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(10)
                    }
                    if a.isLocked && !a.isAnchor {
                        Text("Kept")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(10)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: a.isLocked)
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(g.displayName)
                            .font(.body.weight(.semibold))
                        Text(a.slot.displayLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    AvailabilityBadge(token: g.availabilityToken)
                }
                compositionTileActionRow(a)
            }
            .modifier(FilledTileAccess(
                label: filledTileLabel(a, g),
                isAnchor: a.isAnchor,
                isLocked: a.isLocked,
                suppressEngineActions: model.outfitEngineActionsDisabled,
                onSwap: { onSwap(a.slot) },
                onKeep: { keepTapped(slot: a.slot, assignmentId: a.id) },
                onUnlock: { model.setAssignmentLocked(slot: a.slot, locked: false, assignmentId: a.id) },
                onChangeAnchor: onChangeAnchor
            ))
        } else if let reason = a.gapReason {
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .overlay { Image(systemName: "plus.circle").foregroundStyle(.secondary) }
                BoardTileActionRow {
                    boardMiniAction(
                        "Find \(a.slot.displayLabel.lowercased())",
                        disabled: model.isOffline || model.outfitEngineActionsDisabled
                    ) { onSwap(a.slot) }
                    .accessibilityHint(
                        model.outfitEngineActionsDisabled
                            ? DressingCopy.deviceAccessRequiredHint
                            : ""
                    )
                    .accessibilityLabel("Find \(a.slot.displayLabel.lowercased())")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Gap · \(a.slot.displayLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(reason)
                        .font(.subheadline)
                }
            }
            .padding(10)
            .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Empty \(a.slot.displayLabel). \(reason)")
            .accessibilityAction(named: "Find \(a.slot.displayLabel)") {
                guard !model.outfitEngineActionsDisabled else { return }
                onSwap(a.slot)
            }
        }
    }

    @ViewBuilder
    private func compositionTileActionRow(_ a: StubOutfitAssignment) -> some View {
        BoardTileActionRow {
            if a.isAnchor {
                boardMiniAction(
                    "Change starting item",
                    disabled: model.isOffline || model.outfitEngineActionsDisabled
                ) { onChangeAnchor() }
                .accessibilityHint(
                    model.outfitEngineActionsDisabled
                        ? DressingCopy.deviceAccessRequiredHint
                        : ""
                )
            } else if a.isLocked {
                boardMiniAction("Unlock") {
                    model.setAssignmentLocked(slot: a.slot, locked: false, assignmentId: a.id)
                }
                .accessibilityHint("Allows swapping this piece again")
            } else {
                if !model.isOffline {
                    boardMiniAction(
                        "Swap",
                        disabled: model.outfitEngineActionsDisabled
                    ) { onSwap(a.slot) }
                    .accessibilityHint(
                        model.outfitEngineActionsDisabled
                            ? DressingCopy.deviceAccessRequiredHint
                            : ""
                    )
                }
                boardMiniAction("Keep") { keepTapped(slot: a.slot, assignmentId: a.id) }
                    .accessibilityHint("Kept pieces survive Try another")
            }
        }
    }

    private func skeletonTile(_ a: StubOutfitAssignment) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.18))
                .frame(width: 120, height: 140)
            VStack(alignment: .leading, spacing: 6) {
                Text(a.slot.displayLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.22))
                    .frame(height: 14)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.16))
                    .frame(width: 120, height: 12)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(a.slot.displayLabel), loading placeholder")
    }

    @ViewBuilder
    private func accessoryTile(_ a: StubOutfitAssignment) -> some View {
        // Anchors are rendered via compositionTile in the main column (#61).
        if a.isAnchor {
            EmptyView()
        } else if a.isSkeletonPlaceholder {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.18))
                    .frame(width: 88, height: 88)
                Text(a.slot.displayLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else if let gid = a.garmentId, let g = model.garments.first(where: { $0.id == gid }) {
            let unavailable = g.availability != "AVAILABLE"
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    FixtureImageView(garment: g, height: 88, presentation: .tiny)
                        .frame(width: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .opacity(unavailable ? 0.45 : 1.0)
                    if a.isLocked {
                        Text("Kept")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(4)
                            .accessibilityHidden(true)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: a.isLocked)
                Text(g.displayName)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 88)
                Text(a.slot.displayLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 88)
                BoardTileActionRow {
                    if a.isLocked {
                        boardMiniAction("Unlock") {
                            model.setAssignmentLocked(slot: a.slot, locked: false, assignmentId: a.id)
                        }
                    } else {
                        if !model.isOffline {
                            boardMiniAction(
                                "Swap",
                                disabled: model.outfitEngineActionsDisabled
                            ) { onSwap(a.slot) }
                            .accessibilityHint(
                                model.outfitEngineActionsDisabled
                                    ? DressingCopy.deviceAccessRequiredHint
                                    : ""
                            )
                        }
                        boardMiniAction("Keep") { keepTapped(slot: a.slot, assignmentId: a.id) }
                    }
                }
                .frame(width: 88)
            }
            .modifier(FilledTileAccess(
                label: filledTileLabel(a, g),
                isAnchor: false,
                isLocked: a.isLocked,
                suppressEngineActions: model.outfitEngineActionsDisabled,
                onSwap: { onSwap(a.slot) },
                onKeep: { keepTapped(slot: a.slot, assignmentId: a.id) },
                onUnlock: { model.setAssignmentLocked(slot: a.slot, locked: false, assignmentId: a.id) },
                onChangeAnchor: onChangeAnchor
            ))
        } else if a.gapReason != nil {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                    .frame(width: 88, height: 88)
                Text("Gap")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                BoardTileActionRow {
                    boardMiniAction(
                        "Find accessory",
                        disabled: model.isOffline || model.outfitEngineActionsDisabled
                    ) { onSwap(a.slot) }
                    .accessibilityHint(
                        model.outfitEngineActionsDisabled
                            ? DressingCopy.deviceAccessRequiredHint
                            : ""
                    )
                }
                .frame(width: 88)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Empty accessory")
            .accessibilityAction(named: "Find accessory") {
                guard !model.outfitEngineActionsDisabled else { return }
                onSwap(a.slot)
            }
        }
    }
}

/// Mini bordered actions under board tiles (#134).
private struct BoardTileActionRow<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 8) {
            content()
            Spacer(minLength: 0)
        }
    }
}

/// Combined-tile VoiceOver: label + custom actions so Swap/Keep are never swallowed (#128).
private struct FilledTileAccess: ViewModifier {
    var label: String
    var isAnchor: Bool
    var isLocked: Bool
    var suppressEngineActions: Bool
    var onSwap: () -> Void
    var onKeep: () -> Void
    var onUnlock: () -> Void
    var onChangeAnchor: () -> Void

    func body(content: Content) -> some View {
        Group {
            if isAnchor {
                if suppressEngineActions {
                    content
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(label)
                } else {
                    content
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(label)
                        .accessibilityAction(named: "Change starting item", onChangeAnchor)
                }
            } else if isLocked {
                content
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(label)
                    .accessibilityAction(named: "Unlock", onUnlock)
            } else if suppressEngineActions {
                content
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(label)
                    .accessibilityAction(named: "Keep", onKeep)
            } else {
                content
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(label)
                    .accessibilityAction(named: "Swap", onSwap)
                    .accessibilityAction(named: "Keep", onKeep)
            }
        }
    }
}

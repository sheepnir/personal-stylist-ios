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
    /// Sprint 9: false under the tab shell — opening the Outfit tab never starts a
    /// generation (and never a paid request). Building stays an explicit user action.
    var autoBuildsOnAppear: Bool = true

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var contextExpanded = false
    @AppStorage("demo.boardKeepTipShown") private var boardKeepTipShown = false
    @AppStorage(StylingModel.defaultsKey) private var selectedStylingModel = StylingModel.jev.rawValue
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
                Picker("Stylist for next request", selection: $selectedStylingModel) {
                    ForEach(StylingModel.allCases) { option in Text(option.title).tag(option.rawValue) }
                }
                .pickerStyle(.menu)
                .disabled(model.isGenerating || model.isLoadingAlternatives)
                .accessibilityHint("Select a model, then update the outfit to compare with the same weather and occasion.")
                .onChange(of: selectedStylingModel) { _, _ in model.markContextChanged() }
                Text("Enable each model’s suggestions in Profile before using it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let current = model.outfit {
                    Text("Generated with: \(StylingModel.resultTitle(current.generation?.modelId))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if model.deviceAccessRejected {
                    deviceAccessFailureBanner()
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
                    if let notice = model.boardFallbackNotice {
                        fallbackNotice(notice)
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
            if autoBuildsOnAppear, model.outfit == nil, !model.isGenerating,
               model.generateFailureMessage == nil, !model.deviceAccessRejected {
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
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
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
        hint: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        DailyWearA11yButton(
            identifier: "board.action.\(title)",
            label: title,
            hint: hint,
            isEnabled: !disabled,
            action: action
        ) {
            Text(title)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.secondary.opacity(0.45), lineWidth: 1)
                )
        }
    }

    private func keepTapped(slot: StubSlot, assignmentId: UUID) {
        model.setAssignmentLocked(slot: slot, locked: true, assignmentId: assignmentId)
        if !boardKeepTipShown {
            boardKeepTipShown = true
            showKeepTipBanner = true
        }
    }

    /// #45 / #46 — inline, not dismissible or tappable; one combined VoiceOver element.
    private func fallbackNotice(_ notice: FallbackNotice) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: AssetLibrary.Symbol.info)
                .foregroundStyle(AssetLibrary.Palette.statusInfo)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(notice.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(notice.body)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AssetLibrary.Palette.surfaceBannerInfo, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(notice.accessibilityLabel)
        .accessibilityIdentifier("board.fallbackNotice")
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

    private func deviceAccessFailureBanner() -> some View {
        let title = DressingCopy.deviceAccessRejectedTitle
        let body = model.outfit != nil
            ? DressingCopy.deviceAccessRejectedWithOutfit
            : DressingCopy.deviceAccessRejectedNoOutfit
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
            DisclosureGroup(isExpanded: $contextExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Occasion", selection: $model.occasion) {
                        ForEach(DayOccasion.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minHeight: 44)
                    .accessibilityHint("Applies to your next explicit outfit request")
                    Picker("Temperature", selection: $model.temperatureBand) {
                        ForEach(TempBand.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minHeight: 44)
                    .accessibilityHint("Choose the weather manually")
                    Toggle("Rain", isOn: $model.rain)
                        .frame(minHeight: 44)
                    Button("Use these choices for today") { model.confirmManualContext() }
                        .buttonStyle(.bordered)
                        .frame(minHeight: 44)
                        .accessibilityHint("Confirms the weather without generating an outfit")
                }
                .padding(.top, 8)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Outfit context · Edit")
                        .font(.subheadline.weight(.semibold))
                    Text(model.manualContext.summary)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(minHeight: 44)
            }
            // Refresh the date label while the app stays open over local midnight.
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                Text(model.contextReviewCopy)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.contextRequestCancelled {
                Text("Context changed. The pending result won’t be used. Generate or Swap again when you’re ready.")
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.contextDirty, !(model.isGenerating && model.generateIntent == .updateContext) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Settings changed")
                        .font(.subheadline.weight(.semibold))
                    Text("Your outfit still uses the previous settings. Update when you’re ready.")
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
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: a.isLocked)
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
            .accessibilityElement(children: .contain)
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
                        disabled: model.isOffline || model.outfitEngineActionsDisabled,
                        hint: model.outfitEngineActionsDisabled
                            ? DressingCopy.deviceAccessRequiredHint
                            : nil
                    ) { onSwap(a.slot) }
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
            .accessibilityElement(children: .contain)
        }
    }

    @ViewBuilder
    private func compositionTileActionRow(_ a: StubOutfitAssignment) -> some View {
        BoardTileActionRow {
            if a.isAnchor {
                boardMiniAction(
                    "Change starting item",
                    disabled: model.isOffline || model.outfitEngineActionsDisabled,
                    hint: model.outfitEngineActionsDisabled
                        ? DressingCopy.deviceAccessRequiredHint
                        : nil
                ) { onChangeAnchor() }
            } else if a.isLocked {
                boardMiniAction(
                    "Unlock",
                    hint: "Allows swapping this piece again"
                ) {
                    model.setAssignmentLocked(slot: a.slot, locked: false, assignmentId: a.id)
                }
            } else {
                if !model.isOffline {
                    boardMiniAction(
                        "Swap",
                        disabled: model.outfitEngineActionsDisabled,
                        hint: model.outfitEngineActionsDisabled
                            ? DressingCopy.deviceAccessRequiredHint
                            : nil
                    ) { onSwap(a.slot) }
                }
                boardMiniAction(
                    "Keep",
                    hint: "Kept pieces survive Try another"
                ) { keepTapped(slot: a.slot, assignmentId: a.id) }
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
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: a.isLocked)
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
                        boardMiniAction(
                            "Unlock",
                            hint: "Allows swapping this piece again"
                        ) {
                            model.setAssignmentLocked(slot: a.slot, locked: false, assignmentId: a.id)
                        }
                    } else {
                        if !model.isOffline {
                            boardMiniAction(
                                "Swap",
                                disabled: model.outfitEngineActionsDisabled,
                                hint: model.outfitEngineActionsDisabled
                                    ? DressingCopy.deviceAccessRequiredHint
                                    : nil
                            ) { onSwap(a.slot) }
                        }
                        boardMiniAction(
                            "Keep",
                            hint: "Kept pieces survive Try another"
                        ) { keepTapped(slot: a.slot, assignmentId: a.id) }
                    }
                }
                .frame(width: 88)
            }
            .accessibilityElement(children: .contain)
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
                        disabled: model.isOffline || model.outfitEngineActionsDisabled,
                        hint: model.outfitEngineActionsDisabled
                            ? DressingCopy.deviceAccessRequiredHint
                            : nil
                    ) { onSwap(a.slot) }
                }
                .frame(width: 88)
            }
            .accessibilityElement(children: .contain)
        }
    }
}

/// When device access is rejected, Find and Swap stay disabled buttons.
/// They are not custom actions that can fire while the button is disabled.
enum OutfitBoardAccessibilityPolicy {
    static func exposesEngineBypassVoiceOverActions(suppressEngineActions: Bool) -> Bool {
        !suppressEngineActions
    }
}

/// Mini bordered actions under board tiles (#134).
private struct BoardTileActionRow<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                content()
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 8) { content() }
        }
    }
}


import SwiftUI
import PhotosUI
import UIKit

/// M1-F03-01/02/05 — grid + composable filters/result count + long-press availability.
struct WardrobeGridView: View {
    @ObservedObject var model: LoopDemoModel
    var onSelect: (StubGarment) -> Void
    var onBuild: (StubGarment) -> Void
    var onOpenProfile: () -> Void = {}
    var onOpenDiagnostics: () -> Void = {}
    /// GH #53 — Change starting item picker chrome.
    var isPickingAnchor: Bool = false
    var onCancelPick: (() -> Void)? = nil
    /// Resume board without regenerating when an outfit session exists.
    var onReturnToOutfit: (() -> Void)? = nil
    /// D-75 — open today’s persisted log (read-only; correction is the write path).
    var onOpenLoggedToday: (() -> Void)? = nil

    @State private var selectedSlots: Set<StubSlot> = []
    @State private var selectedAvailability: Set<AvailabilityToken> = []
    @State private var readinessFilter: ReadinessFilter = .all
    @State private var finishDetailsId: UUID?
    @AppStorage("didSeeAvailabilityLongPressTip") private var didSeeAvailabilityLongPressTip = false
    @State private var sort: WardrobeSort = WardrobeSort.productDefault
    @State private var showAddSheet = false
    @State private var showFixturePicker = false
    @State private var selectedFixtureForAdd: StubGarment?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var photoLoadError: String?
    @State private var showFilterSheet = false
    @StateObject private var cameraSession = CameraIntakeSession()
    /// GH #121 — sample name already in wardrobe; prompt for a distinguishing name.
    @State private var pendingSampleNameConflict: PendingSampleNameConflict?

    @State private var filterCache = WardrobeFilterCache()

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    private struct PendingSampleNameConflict: Identifiable {
        let id = UUID()
        let fixture: StubGarment
        let suggestedName: String
    }

    private enum ReadinessFilter: String, CaseIterable, Identifiable, Hashable {
        case all = "All"
        case ready = "Ready"
        case draft = "Drafts"
        var id: String { rawValue }
    }

    /// M1-F03-03 / #115 — Sort lives in the Filter sheet (PRD §7.3).
    private enum WardrobeSort: String, CaseIterable, Identifiable, Hashable {
        case newestIntake = "Recently added"
        case slot = "Slot"
        case leastWorn = "Least worn"
        case longestSinceWorn = "Longest since worn"
        case highestCostPerWear = "Highest cost per wear"
        var id: String { rawValue }

        static let productDefault: WardrobeSort = .newestIntake
    }

    private var draftCount: Int { model.visibleGarments.filter { !$0.isReady }.count }

    /// Recomputes filter and sort only when the wardrobe or the controls change (#160).
    private func displayedGarments() -> [StubGarment] {
        filterCache.resolve(filterSignature, compute: computeFiltered)
    }

    private var filterSignature: Int {
        var hasher = Hasher()
        hasher.combine(sort)
        hasher.combine(readinessFilter)
        hasher.combine(selectedSlots)
        hasher.combine(selectedAvailability)
        for garment in model.visibleGarments {
            hasher.combine(garment)
            hasher.combine(model.wearCount(for: garment.id))
        }
        return hasher.finalize()
    }

    private func computeFiltered() -> [StubGarment] {
        let referenceDate = Date()
        return model.visibleGarments.filter { g in
            if !selectedSlots.isEmpty && !selectedSlots.contains(g.slot) { return false }
            if !selectedAvailability.isEmpty && !selectedAvailability.contains(g.availabilityToken) { return false }
            switch readinessFilter {
            case .all: break
            case .ready: if !g.isReady { return false }
            case .draft: if g.isReady { return false }
            }
            return true
        }
        .sorted { a, b in
            switch sort {
            case .longestSinceWorn:
                if a.lastWornSortKey != b.lastWornSortKey {
                    return a.lastWornSortKey < b.lastWornSortKey
                }
                return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
            case .slot:
                if a.slot != b.slot { return a.slot.wearingOrderIndex < b.slot.wearingOrderIndex }
                return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
            case .newestIntake:
                let aDate = a.intakeSortDate(referenceDate: referenceDate)
                let bDate = b.intakeSortDate(referenceDate: referenceDate)
                if aDate != bDate { return aDate > bDate }
                return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
            case .leastWorn:
                let aw = totalWearCount(a)
                let bw = totalWearCount(b)
                if aw != bw { return aw < bw }
                return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
            case .highestCostPerWear:
                let ac = costPerWearSortKey(a)
                let bc = costPerWearSortKey(b)
                switch (ac, bc) {
                case let (.some(aVal), .some(bVal)):
                    if aVal != bVal { return aVal > bVal }
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): break
                }
                return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
            }
        }
    }

    private func totalWearCount(_ g: StubGarment) -> Int {
        let confirmed = model.wearCount(for: g.id)
        if let bucket = g.priorWearBucket,
           let known = PriorWearBucket(rawValue: bucket) {
            return known.midpoint + confirmed
        }
        if let estimate = g.priorWearEstimate, estimate > 0 {
            return estimate + confirmed
        }
        return confirmed
    }

    private func costPerWearSortKey(_ g: StubGarment) -> Decimal? {
        guard let price = g.purchasePrice, price > 0 else { return nil }
        let wears = max(1, totalWearCount(g))
        return price / Decimal(wears)
    }

    private var activeFilterCount: Int {
        var count = 0
        if readinessFilter != .all { count += 1 }
        count += selectedSlots.count
        count += selectedAvailability.count
        if sort != WardrobeSort.productDefault { count += 1 }
        return count
    }

    private var profileNeedsConfirm: Bool { model.styleProfile?.confirmedAt == nil }

    private var filtersActive: Bool {
        !selectedSlots.isEmpty || !selectedAvailability.isEmpty || readinessFilter != .all
    }

    @ViewBuilder
    private var singleWardrobeBanner: some View {
        if isPickingAnchor {
            anchorPickBanner
        } else if profileNeedsConfirm {
            profileConfirmBanner
        } else if draftCount > 0 {
            VStack(alignment: .leading, spacing: 8) {
                draftsBanner
                dailyWearWardrobeBanner
            }
        } else {
            dailyWearWardrobeBanner
        }
    }

    @ViewBuilder
    private var dailyWearWardrobeBanner: some View {
        if model.showsLoggedTodayRow, let snapshot = model.loggedTodaySnapshot() {
            loggedTodayBanner(snapshot)
        } else if model.showsReturnToOutfitBanner, let onReturnToOutfit {
            returnToOutfitBanner(onReturnToOutfit)
        }
    }

    var body: some View {
        CameraIntakeHost(session: cameraSession, onTryAgain: handleTakePhotoTap) {
            wardrobeChrome
        }
    }

    private var wardrobeChrome: some View {
        let displayed = displayedGarments()
        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                filterChrome
                singleWardrobeBanner
                coverageBlock
                resultCountRow
                Button { showFilterSheet = true } label: {
                    Text("Sort: \(sort.rawValue)")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .accessibilityHint("Change wardrobe sort in Filter")
                if model.isLoadingWardrobe && model.garments.isEmpty {
                    wardrobeLoadingGrid
                } else if displayed.isEmpty {
                    ContentUnavailableView(
                        filtersActive ? "No garments match" : "No garments",
                        systemImage: "tshirt",
                        description: Text(filtersActive ? "Clear filters to see the full wardrobe." : (model.wardrobeCoverage.coverageLine ?? "Add garments to get started."))
                    )
                    .frame(maxWidth: .infinity, minHeight: 180)
                    if filtersActive {
                        Button("Clear filters") { clearFilters() }
                            .frame(minHeight: 44)
                    } else if model.garments.isEmpty {
                        Button("Add your first piece") {
                            showAddSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(minHeight: 44)
                        .accessibilityLabel("Add your first piece")
                        .accessibilityHint(CameraIntakeCopy.takePhotoHint)
                    }
                } else {
                    EquatableGarmentGrid(
                        garments: displayed,
                        isPickingAnchor: isPickingAnchor,
                        showTip: !didSeeAvailabilityLongPressTip,
                        columns: columns,
                        cell: { garment, tip in
                            AnyView(self.cell(garment, showLongPressTip: tip))
                        }
                    )
                    .equatable()
                }
            }
            .padding()
        }
        .navigationTitle(isPickingAnchor ? "Choose starting item" : "Wardrobe")
        .toolbar {
            if isPickingAnchor {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancelPick?() }
                        .accessibilityLabel("Cancel — return to outfit")
                }
            }
            if !isPickingAnchor && !model.garments.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .accessibilityLabel("Add garment")
                    .accessibilityHint("Take a photo, choose from Photos, or use a sample piece")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onOpenProfile()
                } label: {
                    Label("Profile", systemImage: model.styleProfile?.isDraft == true ? "person.crop.circle.badge.clock" : "person.crop.circle")
                }
                .accessibilityLabel("Style profile")
                .accessibilityHint("Opens your style profile")
                .accessibilityValue(model.styleProfile?.isDraft == true ? "Unconfirmed" : "")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("Show retired", isOn: $model.showRetired)
                    #if DEBUG
                    Divider()
                    Button {
                        onOpenDiagnostics()
                    } label: {
                        Label("Diagnostics", systemImage: "ladybug")
                    }
                    #endif
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .accessibilityLabel("More")
                .accessibilityHint("Wardrobe options")
            }
        }
        .sheet(isPresented: $showFilterSheet) {
            filterSheet
        }
        .sheet(isPresented: Binding(
                get: { finishDetailsId != nil },
                set: { if !$0 { finishDetailsId = nil } }
            )) {
                if let id = finishDetailsId {
                    FinishDetailsSheet(model: model, garmentId: id, mode: .finishDetails) {
                        finishDetailsId = nil
                    }
                }
            }
        .sheet(isPresented: $showAddSheet) {
            addGarmentSheet
        }
        .sheet(isPresented: $showFixturePicker) {
            fixturePickerSheet
        }
        .sheet(isPresented: Binding(
                get: { selectedFixtureForAdd != nil },
                set: { if !$0 { selectedFixtureForAdd = nil } }
            )) {
                if let fixture = selectedFixtureForAdd {
                    FinishDetailsSheet(model: model, garmentId: fixture.id, mode: .finishDetails) {
                        selectedFixtureForAdd = nil
                    }
                }
            }
        .onAppear {
            cameraSession.attach(model)
            if ProcessInfo.processInfo.arguments.contains("-demoFilters") {
                selectedAvailability = [.laundry, .packed]
                readinessFilter = .ready
            }
            if ProcessInfo.processInfo.arguments.contains("-demoSort") {
                sort = .longestSinceWorn
                readinessFilter = .all
                selectedAvailability.removeAll()
                selectedSlots.removeAll()
            }
        }
    }

    private var wardrobeLoadingGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(0..<6, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 120)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.12))
                        .frame(height: 14)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 80, height: 12)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.secondary.opacity(0.06))
                )
                .redacted(reason: .placeholder)
            }
        }
        .accessibilityLabel("Loading wardrobe")
    }

    @ViewBuilder
    private var coverageBlock: some View {
        let snap = model.wardrobeCoverage
        if let line = snap.coverageLine {
            Text(line)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel(line)
        } else if let tip = snap.thinSuggestion {
            Text(tip)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(tip)
        }
    }

    private var filterChrome: some View {
        fadingHorizontalChipRow {
            filterButton
            quickChip("Available", selected: selectedAvailability.contains(.available)) {
                toggle(.available, in: &selectedAvailability)
            }
            quickChip("Drafts", selected: readinessFilter == .draft) {
                readinessFilter = readinessFilter == .draft ? .all : .draft
            }
            quickChip("Top", selected: selectedSlots.contains(.top)) {
                toggle(.top, in: &selectedSlots)
            }
            quickChip("Bottom", selected: selectedSlots.contains(.bottom)) {
                toggle(.bottom, in: &selectedSlots)
            }
        }
    }

    private var filterButton: some View {
        Button {
            showFilterSheet = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
                if activeFilterCount > 0 {
                    Text("\(activeFilterCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.accentColor, in: Capsule())
                        .offset(x: 6, y: -6)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityLabel("Filter")
        .accessibilityValue(activeFilterCount > 0 ? "\(activeFilterCount) filters active" : "No filters")
        .accessibilityHint("Opens filter and sort options")
    }

    private func quickChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        chip(title, selected: selected, action: action)
    }

    private func fadingHorizontalChipRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack(alignment: .trailing) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    content()
                }
                .padding(.trailing, 28)
            }
            LinearGradient(
                colors: [Color(.systemBackground).opacity(0), Color(.systemBackground)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 24)
            .allowsHitTesting(false)
        }
    }

    private var resultCountRow: some View {
        HStack(spacing: 4) {
            if filtersActive {
                Text("Showing \(displayedGarments().count) of \(model.visibleGarments.count)")
                    .font(.subheadline.weight(.semibold))
                Text("·")
                    .foregroundStyle(.secondary)
                Text("Filtered")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Clear") { clearFilters() }
                    .font(.subheadline.weight(.semibold))
            } else {
                Text("Showing \(displayedGarments().count)")
                    .font(.subheadline.weight(.semibold))
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            filtersActive
                ? "Showing \(displayedGarments().count) of \(model.visibleGarments.count), filtered"
                : "Showing \(displayedGarments().count) garments"
        )
    }


    private var anchorPickBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Choose a new starting item")
                .font(.subheadline.weight(.semibold))
            Text("Your current outfit stays until you Build around a READY, available piece. Cancel returns without regenerating.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Return to outfit") { onCancelPick?() }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
    }

    private func returnToOutfitBanner(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(DailyWearCopy.returnToOutfit, systemImage: "square.stack.3d.up")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(DailyWearCopy.returnToOutfit)
        .accessibilityHint("Opens the current board without regenerating")
    }

    private func loggedTodayBanner(_ snapshot: DailyWearTodaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            DailyWearA11yButton(
                identifier: "dailyWear.loggedToday",
                label: DailyWearCopy.rowAccessibility(
                    leadName: snapshot.leadName,
                    extraCount: snapshot.extraCount,
                    wornOn: snapshot.event.wornOn
                ),
                hint: DailyWearCopy.loggedTodayHint,
                value: model.showsReplacingUnloggedSessionNote ? DailyWearCopy.replacingSession : "",
                action: { onOpenLoggedToday?() }
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(DailyWearCopy.loggedToday)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(
                        DailyWearCopy.rowLine(
                            leadName: snapshot.leadName,
                            extraCount: snapshot.extraCount,
                            wornOn: snapshot.event.wornOn
                        )
                    )
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(10)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }
            .frame(maxWidth: .infinity, minHeight: 44)

            if model.showsReplacingUnloggedSessionNote {
                Text(DailyWearCopy.replacingSession)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var profileConfirmBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.blue)
                Text("Confirm your style profile to generate outfits")
                    .font(.subheadline)
            }
            Button("Confirm profile") {
                onOpenProfile()
            }
            .buttonStyle(.borderedProminent)
            .frame(minHeight: 44)
            .accessibilityLabel("Confirm profile")
            .accessibilityHint("Required before generating outfits")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private var draftsBanner: some View {
        Button {
            if let draft = model.visibleGarments.first(where: { !$0.isReady }) {
                finishDetailsId = draft.id
            }
        } label: {
            Label(model.wardrobeCoverage.draftsLine ?? "\(draftCount) garments need details before they can be used", systemImage: "exclamationmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func cell(_ g: StubGarment, showLongPressTip: Bool) -> some View {
        Button {
            // GH #96: in Change starting item mode, commit immediately — do not push Review.
            if isPickingAnchor {
                onBuild(g)
            } else {
                onSelect(g)
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    FixtureImageView(garment: g, height: 120, presentation: .card)
                    if !g.isReady {
                        Text("Draft")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.orange, in: Capsule())
                            .foregroundStyle(.white)
                            .padding(6)
                    }
                }
                Text(g.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                AvailabilityBadge(token: g.availabilityToken)
                if !g.isReady {
                    Text("Finish details")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.secondary.opacity(g.isReady ? 0.06 : 0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(!g.isReady ? Color.orange.opacity(0.5) : Color.clear, lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(g.displayName), \(g.availabilityToken.accessibilityName)\(!g.isReady ? ", draft" : "")")
        .accessibilityIdentifier("wardrobe.card.\(g.id.uuidString)")
        .accessibilityHint(
            isPickingAnchor
                ? "Uses this as the new starting item"
                : "Opens garment details. Long press for availability actions."
        )
        .accessibilityAction(named: "Finish details") {
            if !g.isReady { finishDetailsId = g.id }
        }
        .contextMenu {
            if isPickingAnchor {
                Button("Use as starting item") { onBuild(g) }
            } else {
                Button("Open garment") { onSelect(g) }
                if !g.isReady {
                    Button("Finish details") { finishDetailsId = g.id }
                }
            }
            Divider()
            ForEach(AvailabilityToken.allCases, id: \.self) { token in
                Button {
                    model.setAvailability(g.id, token.rawValue)
                } label: {
                    Label(token.accessibilityName, systemImage: token.symbolName)
                }
            }
        }
        .overlay(alignment: .top) {
            if showLongPressTip {
                longPressTipPopover
                    .offset(y: -4)
                    .zIndex(1)
            }
        }
    }

    private var longPressTipPopover: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Press and hold a piece to change availability")
                .font(.footnote)
                .foregroundStyle(.primary)
            Button("Got it") { didSeeAvailabilityLongPressTip = true }
                .font(.footnote.weight(.semibold))
        }
        .padding(10)
        .frame(maxWidth: 260)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 4, y: 2)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var filterSheet: some View {
        NavigationStack {
            Form {
                Section("Readiness") {
                    Picker("Readiness", selection: $readinessFilter) {
                        ForEach(ReadinessFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Readiness")
                }

                Section("Slot") {
                    fadingHorizontalChipRow {
                        ForEach(StubSlot.wearingOrder, id: \.self) { slot in
                            chip(slot.displayLabel, selected: selectedSlots.contains(slot)) {
                                toggle(slot, in: &selectedSlots)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }

                Section("Availability") {
                    fadingHorizontalChipRow {
                        ForEach(AvailabilityToken.allCases.filter { $0 != .retired }, id: \.self) { token in
                            availabilityFilterChip(token)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }

                Section("Sort") {
                    Picker("Sort", selection: $sort) {
                        ForEach(WardrobeSort.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .accessibilityLabel("Sort")
                    .accessibilityValue(sort.rawValue)
                }
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showFilterSheet = false }
                }
                if filtersActive || sort != WardrobeSort.productDefault {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Clear") {
                            clearFilters()
                            sort = WardrobeSort.productDefault
                        }
                    }
                }
            }
        }
        .presentationDetents([.large, .medium])
    }

    private func availabilityFilterChip(_ token: AvailabilityToken) -> some View {
        let selected = selectedAvailability.contains(token)
        return Button {
            toggle(token, in: &selectedAvailability)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: token.symbolName)
                    .foregroundStyle(token.color)
                Text(token.accessibilityName)
                    .font(.subheadline.weight(selected ? .medium : .regular))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(selected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12), in: Capsule())
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityLabel(token.accessibilityName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(selected ? .medium : .regular))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(selected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12), in: Capsule())
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func toggle<T: Hashable>(_ value: T, in set: inout Set<T>) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }

    private func clearFilters() {
        selectedSlots.removeAll()
        selectedAvailability.removeAll()
        readinessFilter = .all
    }

    @ViewBuilder
    private var addGarmentSheet: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        handleTakePhotoTap()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(CameraIntakeCopy.takePhoto)
                                    .font(.body)
                                Text(CameraIntakeCopy.takePhotoSubtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "camera")
                                .font(.title2)
                                .foregroundStyle(.orange)
                        }
                    }
                    .frame(minHeight: 60)
                    .accessibilityLabel(CameraIntakeCopy.takePhoto)
                    .accessibilityHint(CameraIntakeCopy.takePhotoHint)

                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Choose from Photos")
                                    .font(.body)
                                Text("Pick a photo from your library")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "photo.on.rectangle")
                                .font(.title2)
                                .foregroundStyle(.blue)
                        }
                    }
                    .frame(minHeight: 60)
                    .onChange(of: selectedPhotoItem) { _, newItem in
                        Task {
                            await handlePhotoSelection(newItem)
                        }
                    }

                    Button {
                        showAddSheet = false
                        showFixturePicker = true
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Use a sample piece")
                                    .font(.body)
                                Text("Try with a pre-loaded example")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "tshirt")
                                .font(.title2)
                                .foregroundStyle(.green)
                        }
                    }
                    .frame(minHeight: 60)
                }
            }
            .navigationTitle("Add a garment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAddSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
        .alert(
            "Couldn’t add that photo",
            isPresented: Binding(
                get: { photoLoadError != nil },
                set: { if !$0 { photoLoadError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(photoLoadError ?? "")
        }
    }

    private func handleTakePhotoTap() {
        cameraSession.attach(model)
        let state = CameraPermissionPolicy.resolvedState(
            authorization: CameraPermissionPolicy.currentAuthorization(),
            cameraAvailable: CameraPermissionPolicy.isCameraAvailable()
        )
        switch CameraPermissionPolicy.action(for: state) {
        case .requestAccess:
            Task {
                let granted = await CameraPermissionPolicy.requestAccess()
                let available = CameraPermissionPolicy.isCameraAvailable()
                if granted && available {
                    showAddSheet = false
                    cameraSession.apply(.startCapture)
                } else {
                    showAddSheet = false
                    cameraSession.apply(.permissionFallback(granted ? .unavailable : .denied))
                }
            }
        case .presentCamera:
            showAddSheet = false
            cameraSession.apply(.startCapture)
        case .offerSettingsOrFallback:
            showAddSheet = false
            cameraSession.apply(.permissionFallback(state))
        }
    }

    private func handlePhotoSelection(_ item: PhotosPickerItem?) async {
        guard let item else { return }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                await MainActor.run {
                    photoLoadError = "That item had no image data. Try another photo, or use a sample piece."
                    selectedPhotoItem = nil
                }
                return
            }

            let garmentId = UUID()
            let imagePath: String
            do {
                imagePath = try UserGarmentPhotoStore.persistJPEG(from: data, garmentId: garmentId)
            } catch {
                await MainActor.run {
                    photoLoadError = "Couldn’t save that photo on this device. Try another image, or use a sample piece."
                    selectedPhotoItem = nil
                }
                return
            }

            let slot = StubSlot.top
            let newGarment = StubGarment(
                id: garmentId,
                displayName: StubGarment.untitledName(for: slot),
                slot: slot,
                readiness: .draft,
                availability: "AVAILABLE",
                colorPrimary: nil,
                pattern: nil,
                surface: nil,
                imagePath: imagePath,
                formality: nil,
                warmth: nil,
                setId: nil,
                keepTogether: nil,
                lastWornOn: nil,
                daysSinceIntake: 0,
                createdAt: Date(),
                displayNameSource: "DERIVED"
            )

            let saved = await model.addDraftGarment(newGarment)
            await MainActor.run {
                showAddSheet = false
                selectedPhotoItem = nil
                if saved {
                    selectedFixtureForAdd = newGarment
                } else {
                    photoLoadError = "The photo was saved but the garment couldn’t be stored. Try again, or use a sample piece."
                }
            }
        } catch {
            await MainActor.run {
                photoLoadError = "Couldn’t load that photo. The Photos picker doesn’t need full library permission — try another image, or use a sample piece."
                selectedPhotoItem = nil
            }
        }
    }

    @ViewBuilder
    private var fixturePickerSheet: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(FixtureWardrobeLoader.loadGarments()) { fixture in
                        let alreadyOwned = wardrobeContainsDisplayName(fixture.displayName)
                        Button {
                            requestSampleFixture(fixture)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                ZStack(alignment: .topTrailing) {
                                    FixtureImageView(garment: fixture, height: 120, presentation: .card)
                                    if alreadyOwned {
                                        Text("In wardrobe")
                                            .font(.caption2.weight(.bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(.secondary.opacity(0.85), in: Capsule())
                                            .foregroundStyle(.white)
                                            .padding(6)
                                    }
                                }
                                Text(fixture.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(2)
                                    .foregroundStyle(.primary)
                                Text(fixture.slot.displayLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.secondary.opacity(0.06))
                            )
                        }
                        .accessibilityLabel(
                            alreadyOwned
                                ? "\(fixture.displayName), already in wardrobe"
                                : fixture.displayName
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("Use a sample piece")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showFixturePicker = false }
                }
            }
            .alert(
                "Name already in wardrobe",
                isPresented: Binding(
                    get: { pendingSampleNameConflict != nil },
                    set: { if !$0 { pendingSampleNameConflict = nil } }
                ),
                presenting: pendingSampleNameConflict
            ) { conflict in
                Button("Use \"\(conflict.suggestedName)\"") {
                    Task { await commitSampleFixture(conflict.fixture, displayName: conflict.suggestedName) }
                }
                Button("Cancel", role: .cancel) {
                    pendingSampleNameConflict = nil
                }
            } message: { conflict in
                Text("You already have “\(conflict.fixture.displayName)”. Use a distinguishing name so the two stay separate.")
            }
        }
    }

    private func wardrobeContainsDisplayName(_ name: String) -> Bool {
        let needle = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return model.garments.contains {
            $0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == needle
        }
    }

    private func suggestedDistinguishingName(for base: String) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        var n = 2
        while wardrobeContainsDisplayName("\(trimmed) (\(n))") {
            n += 1
        }
        return "\(trimmed) (\(n))"
    }

    private func requestSampleFixture(_ fixture: StubGarment) {
        if wardrobeContainsDisplayName(fixture.displayName) {
            pendingSampleNameConflict = PendingSampleNameConflict(
                fixture: fixture,
                suggestedName: suggestedDistinguishingName(for: fixture.displayName)
            )
            return
        }
        Task { await commitSampleFixture(fixture, displayName: fixture.displayName) }
    }

    @MainActor
    private func commitSampleFixture(_ fixture: StubGarment, displayName: String) async {
        pendingSampleNameConflict = nil
        showFixturePicker = false
        // GH #121 / ux-finish-details §3.2.5: sample arrives Save-ready with fixture attributes.
        let newGarment = StubGarment(
            id: UUID(),
            displayName: displayName,
            slot: fixture.slot,
            readiness: .draft,
            availability: "AVAILABLE",
            colorPrimary: fixture.colorPrimary,
            pattern: fixture.pattern,
            surface: fixture.surface,
            imagePath: fixture.imagePath,
            formality: fixture.formality,
            warmth: fixture.warmth,
            setId: nil,
            keepTogether: nil,
            lastWornOn: nil,
            daysSinceIntake: 0,
            createdAt: Date(),
            displayNameSource: displayName == fixture.displayName ? "DERIVED" : "USER"
        )
        let saved = await model.addDraftGarment(newGarment)
        if saved {
            selectedFixtureForAdd = newGarment
        }
    }
}

/// Skips rebuilding wardrobe cells when an unrelated `@Published` change redraws the screen (#159).
private struct EquatableGarmentGrid: View, Equatable {
    let garments: [StubGarment]
    let isPickingAnchor: Bool
    let showTip: Bool
    let columns: [GridItem]
    let cell: (StubGarment, Bool) -> AnyView

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.garments == rhs.garments && lhs.showTip == rhs.showTip
            && lhs.isPickingAnchor == rhs.isPickingAnchor
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(Array(garments.enumerated()), id: \.element.id) { index, garment in
                cell(garment, index == 0 && showTip)
            }
        }
    }
}

/// Holds the last filter+sort result so `body` can run without sorting again (#160).
private final class WardrobeFilterCache {
    private var signature: Int?
    private var rows: [StubGarment] = []

    func resolve(_ signature: Int, compute: () -> [StubGarment]) -> [StubGarment] {
        if self.signature == signature { return rows }
        self.signature = signature
        rows = compute()
        return rows
    }
}

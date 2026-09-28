import SwiftUI

/// Core-loop shell: Wardrobe → Detail, Outfit → Swap → Wear, Calendar, Profile.
/// One shared `LoopDemoModel` (one current outfit); one navigation stack per tab (#124).
struct ContentView: View {
    @StateObject private var model: LoopDemoModel

    init(store: PersistenceStore = InMemoryPersistenceStore.shared) {
        _model = StateObject(wrappedValue: LoopDemoModel(store: store))
    }
    @State private var selectedTab: AppTab = .wardrobe
    @State private var wardrobePath = NavigationPath()
    @State private var outfitPath = NavigationPath()
    @State private var calendarPath = NavigationPath()
    @State private var showSwap = false
    /// F05-04 / GH #53: wardrobe is in Change starting item picker mode.
    @State private var changingAnchor = false
#if DEBUG
    @State private var showDiagnostics = false
#endif
    /// Snapshot of board session until a replacement is committed (or Cancel).
    @State private var outfitBeforeAnchorPick: StubOutfit? = nil
    @State private var pendingProfileForDeviceAccess = false
    /// Profile tab leave guard: unsaved edits are never saved or discarded silently.
    @State private var profileHasUnsavedChanges = false
    /// Drives the Save / Discard / Keep editing dialog (cleared when it closes).
    @State private var tabAwaitingProfileDecision: AppTab?
    /// Where to go once Save or Discard has been applied. Kept apart from the dialog
    /// binding, which SwiftUI clears as the dialog closes.
    @State private var pendingProfileDestination: AppTab?
    @State private var profileCommand: ProfileEditorCommand?

    private enum WardrobeRoute: Hashable {
        case review
    }

    private enum OutfitRoute: Hashable {
        case wearSuccess
        case wear
    }

    private var tabSelection: Binding<AppTab> {
        Binding(get: { selectedTab }, set: { requestTab($0) })
    }

    var body: some View {
        TabView(selection: tabSelection) {
            wardrobeTab
                .tabItem { Label("Wardrobe", systemImage: "tshirt") }
                .tag(AppTab.wardrobe)
            outfitTab
                .tabItem { Label("Outfit", systemImage: "square.stack.3d.up") }
                .tag(AppTab.outfit)
            calendarTab
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(AppTab.calendar)
            profileTab
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(AppTab.profile)
        }
        .task {
            await model.load()
            await applyDemoLaunchArguments()
        }
        .sheet(isPresented: $showSwap, onDismiss: {
            if pendingProfileForDeviceAccess {
                pendingProfileForDeviceAccess = false
                openDeviceAccess()
            }
        }) {
            SwapSheetView(
                model: model,
                onClose: { showSwap = false },
                onChangeStartingItem: {
                    showSwap = false
                    beginAnchorPick()
                },
                onOpenWardrobe: {
                    showSwap = false
                    wardrobePath = NavigationPath()
                    requestTab(.wardrobe)
                },
                onSetUpDeviceAccess: {
                    pendingProfileForDeviceAccess = true
                    showSwap = false
                }
            )
        }
        .confirmationDialog(
            ProfileLeaveCopy.title,
            isPresented: Binding(
                get: { tabAwaitingProfileDecision != nil },
                set: { if !$0 { tabAwaitingProfileDecision = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(ProfileLeaveCopy.save) {
                profileCommand = ProfileEditorCommand(action: .save)
            }
            Button(ProfileLeaveCopy.discard, role: .destructive) {
                profileCommand = ProfileEditorCommand(action: .discard)
            }
            Button(ProfileLeaveCopy.keepEditing, role: .cancel) {
                tabAwaitingProfileDecision = nil
                pendingProfileDestination = nil
            }
        } message: {
            Text(ProfileLeaveCopy.message)
        }
#if DEBUG
        .sheet(isPresented: $showDiagnostics) {
            DemoDiagnosticsSheet(model: model)
        }
#endif
    }

    // MARK: - Tabs

    private var wardrobeTab: some View {
        NavigationStack(path: $wardrobePath) {
            WardrobeGridView(
                model: model,
                onSelect: { g in
                    model.select(g)
                    wardrobePath.append(WardrobeRoute.review)
                },
                onBuild: { g in
                    Task { await buildFromWardrobe(g) }
                },
                onOpenProfile: {
                    requestTab(.profile)
                },
                onOpenDiagnostics: {
                    #if DEBUG
                    showDiagnostics = true
                    #endif
                },
                isPickingAnchor: changingAnchor,
                onCancelPick: {
                    cancelAnchorPick()
                },
                onReturnToOutfit: {
                    resumeOutfitBoard()
                },
                onOpenLoggedToday: {
                    openLoggedToday()
                },
                onSetUpDeviceAccess: {
                    openDeviceAccess()
                }
            )
            .navigationDestination(for: WardrobeRoute.self) { route in
                switch route {
                case .review:
                    ReviewCardView(
                        model: model,
                        onBuild: {
                            Task {
                                if let g = model.selectedGarment {
                                    await buildFromWardrobe(g)
                                }
                            }
                        },
                        onFinishedDetails: {
                            // P0 residual: return to wardrobe after Save from detail sheet
                            wardrobePath = NavigationPath()
                        },
                        onOpenProfile: {
                            requestTab(.profile)
                        },
                        onSetUpDeviceAccess: {
                            openDeviceAccess()
                        }
                    )
                }
            }
#if DEBUG
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showDiagnostics = true
                    } label: {
                        Label("Diagnostics", systemImage: "ladybug")
                    }
                    .accessibilityLabel("Show diagnostics log")
                }
            }
#endif
        }
        .demoToastHost(model: model)
    }

    private var outfitTab: some View {
        NavigationStack(path: $outfitPath) {
            Group {
                if hasBoardContent {
                    OutfitBoardView(
                        model: model,
                        onSwap: { slot in
                            showSwap = true
                            Task { await model.alternatives(for: slot) }
                        },
                        onWear: { outfitPath.append(OutfitRoute.wearSuccess) },
                        onChangeAnchor: {
                            beginAnchorPick()
                        },
                        onChangeWhatIWore: { outfitPath.append(OutfitRoute.wear) },
                        onSetUpDeviceAccess: {
                            openDeviceAccess()
                        },
                        autoBuildsOnAppear: false
                    )
                } else {
                    OutfitEmptyStateView(
                        hasLoggedToday: model.hasLoggedToday,
                        onChooseStartingItem: {
                            wardrobePath = NavigationPath()
                            requestTab(.wardrobe)
                        },
                        onOpenLoggedToday: {
                            outfitPath.append(OutfitRoute.wearSuccess)
                        }
                    )
                }
            }
            .navigationDestination(for: OutfitRoute.self) { route in
                switch route {
                case .wearSuccess:
                    WearSuccessView(
                        model: model,
                        onDone: { finishWearFlow() },
                        onChangeWhatIWore: { outfitPath.append(OutfitRoute.wear) }
                    )
                case .wear:
                    WearConfirmView(model: model) {
                        finishWearFlow()
                    }
                }
            }
        }
        .demoToastHost(model: model)
    }

    private var calendarTab: some View {
        NavigationStack(path: $calendarPath) {
            WearCalendarView(model: model) { garment in
                openGarmentDetail(garment)
            }
        }
        .demoToastHost(model: model)
    }

    private var profileTab: some View {
        NavigationStack {
            ProfileDraftView(
                model: model,
                autosavesOnDisappear: false,
                onUnsavedChangesChange: { profileHasUnsavedChanges = $0 },
                pendingCommand: profileCommand,
                onCommandHandled: { _ in
                    profileCommand = nil
                    profileHasUnsavedChanges = false
                    tabAwaitingProfileDecision = nil
                    let next = pendingProfileDestination
                    pendingProfileDestination = nil
                    if let next { requestTab(next) }
                }
            )
        }
        .demoToastHost(model: model)
    }

    /// The board is shown only when there is something on it. An empty Outfit tab never
    /// starts a generation.
    private var hasBoardContent: Bool {
        model.outfit != nil || model.isGenerating || model.generateFailureMessage != nil
    }

    // MARK: - Navigation

    /// Every tab change goes through here so Profile edits are never saved or dropped silently.
    private func requestTab(_ tab: AppTab) {
        switch TabNavigation.decide(
            from: selectedTab,
            to: tab,
            profileHasUnsavedChanges: profileHasUnsavedChanges,
            isPickingStartingItem: changingAnchor
        ) {
        case .none:
            break
        case .askToSaveProfile(let next):
            pendingProfileDestination = next
            tabAwaitingProfileDecision = next
        case .returnToOutfit:
            cancelAnchorPick()
        case .select(let next):
            selectedTab = next
        }
    }

    private func openDeviceAccess() {
        model.requestScrollToDeviceAccess()
        requestTab(.profile)
    }

    private func openGarmentDetail(_ garment: StubGarment) {
        model.select(garment)
        wardrobePath = NavigationPath()
        wardrobePath.append(WardrobeRoute.review)
        requestTab(.wardrobe)
    }

    private func finishWearFlow() {
        outfitPath = NavigationPath()
        wardrobePath = NavigationPath()
        requestTab(.wardrobe)
    }

    private func beginAnchorPick() {
        outfitBeforeAnchorPick = model.outfit
        changingAnchor = true
        // GH #96: reset to wardrobe root so "Choose starting item" chrome is visible.
        wardrobePath = NavigationPath()
        selectedTab = .wardrobe
    }

    private func cancelAnchorPick() {
        // A starting-item build still in flight must not replace the restored outfit.
        model.cancelGeneration()
        if let snap = outfitBeforeAnchorPick {
            model.outfit = snap
        }
        outfitBeforeAnchorPick = nil
        changingAnchor = false
        model.showToast("Returned to your outfit")
        wardrobePath = NavigationPath()
        outfitPath = NavigationPath()
        selectedTab = .outfit
    }

    private func resumeOutfitBoard() {
        guard model.outfit != nil else { return }
        outfitPath = NavigationPath()
        requestTab(.outfit)
    }

    private func openLoggedToday() {
        guard model.hasLoggedToday else { return }
        if changingAnchor { cancelAnchorPick() }
        outfitPath = NavigationPath()
        outfitPath.append(OutfitRoute.wearSuccess)
        requestTab(.outfit)
    }

    @MainActor
    private func buildFromWardrobe(_ g: StubGarment) async {
        if model.deviceAccessRejected { return }
        // One build at a time: a second result could land on the wrong starting item.
        guard !model.isGenerating else {
            model.showToast(OutfitTabCopy.stillBuilding)
            return
        }
        if changingAnchor {
            let ok = await model.changeAnchor(to: g, priorOutfit: outfitBeforeAnchorPick)
            guard changingAnchor else {
                // The picker was left (Cancel / Outfit tab) while building: that restore wins.
                if !ok { model.generateFailureMessage = nil }
                return
            }
            if ok {
                changingAnchor = false
                outfitBeforeAnchorPick = nil
                // Clean stacks: board only (no leftover review cards).
                wardrobePath = NavigationPath()
                outfitPath = NavigationPath()
                selectedTab = .outfit
            }
            // failure: prior restored in model; stay in picker
            return
        }
        model.select(g)
        guard model.validateBuildPreconditions() else { return }
        outfitPath = NavigationPath()
        requestTab(.outfit)
        await model.buildDemoOutfit(preserveLocks: true, intent: .firstBuild)
    }

    // MARK: - Demo launch arguments (docs/demo-local.md)

    @MainActor
    private func applyDemoLaunchArguments() async {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-demoGrid") || args.contains("-demoFilters") || args.contains("-demoSort") {
            // stay on wardrobe
        } else if args.contains("-demoProfile") {
            selectedTab = .profile
        } else if args.contains("-demoCalendar") {
            selectedTab = .calendar
        } else if args.contains("-demoDetail") {
            if let setMember = model.garments.first(where: { $0.setId != nil && $0.isReady })
                ?? model.garments.first(where: { model.setFor($0) != nil }) {
                model.select(setMember)
            }
            wardrobePath.append(WardrobeRoute.review)
        } else if args.contains("-demoBoard") || args.contains("-demoEngine") {
            model.confirmProfileForDemoIfNeeded()
            if let g = model.selectedGarment { model.select(g) }
            selectedTab = .outfit
            await model.buildDemoOutfit()
        } else if args.contains("-demoWear") {
            model.confirmProfileForDemoIfNeeded()
            await model.buildDemoOutfit()
            selectedTab = .outfit
            await model.wearingThisFromBoard()
            outfitPath.append(OutfitRoute.wearSuccess)
        } else if args.contains("-demoChangeAnchor") {
            model.confirmProfileForDemoIfNeeded()
            await model.buildDemoOutfit()
            // Seed a lock, then Change anchor to another READY available garment
            if var outfit = model.outfit,
               let idx = outfit.assignments.firstIndex(where: { !$0.isAnchor && $0.garmentId != nil }) {
                outfit.assignments[idx].isLocked = true
                model.outfit = outfit
            }
            if let next = model.garments.first(where: {
                $0.isReady && $0.availability == "AVAILABLE" && $0.id != model.selectedGarment?.id
            }) {
                await model.changeAnchor(to: next)
            }
            selectedTab = .outfit
        } else if args.contains("-demoLocks") {
            model.confirmProfileForDemoIfNeeded()
            await model.buildDemoOutfit()
            if var outfit = model.outfit,
               let idx = outfit.assignments.firstIndex(where: { !$0.isAnchor && $0.garmentId != nil }) {
                outfit.assignments[idx].isLocked = true
                model.outfit = outfit
                model.recordDiagnostic("Demo: slot locked for -demoLocks")
            }
            await model.buildDemoOutfit(preserveLocks: true)
            selectedTab = .outfit
        } else if args.contains("-demoSwap") {
            model.confirmProfileForDemoIfNeeded()
            if let g = model.selectedGarment { model.select(g) }
            await model.buildDemoOutfit()
            selectedTab = .outfit
            // Open swap on first non-anchor filled slot
            if let outfit = model.outfit,
               let slot = outfit.assignments.first(where: { !$0.isAnchor && $0.garmentId != nil })?.slot {
                showSwap = true
                await model.alternatives(for: slot)
            }
        } else if args.contains("-demoOffline") {
            model.confirmProfileForDemoIfNeeded()
            model.isOffline = true
            await model.buildDemoOutfit()
            selectedTab = .outfit
        } else if args.contains("-demoReview") {
            wardrobePath.append(WardrobeRoute.review)
        } else if args.contains("-demoFinish") {
            model.confirmProfileForDemoIfNeeded()
            if let draft = model.garments.first(where: { !$0.isReady }) {
                model.select(draft)
                wardrobePath.append(WardrobeRoute.review)
            }
        } else if args.contains("-demoWearHistory") {
            model.confirmProfileForDemoIfNeeded()
            await model.buildDemoOutfit()
            await model.wearingThisFromBoard()
            if let wornId = model.outfit?.assignments.compactMap(\.garmentId).first,
               let g = model.garments.first(where: { $0.id == wornId }) {
                model.select(g)
            }
            wardrobePath.append(WardrobeRoute.review)
        }
    }
}

/// Outfit tab with nothing on the board. Leads to Wardrobe; never generates by itself.
struct OutfitEmptyStateView: View {
    var hasLoggedToday: Bool
    var onChooseStartingItem: () -> Void
    var onOpenLoggedToday: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ContentUnavailableView(
                    OutfitTabCopy.emptyTitle,
                    systemImage: "square.stack.3d.up",
                    description: Text(OutfitTabCopy.emptyMessage)
                )
                Button(OutfitTabCopy.chooseStartingItem) {
                    onChooseStartingItem()
                }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
                .accessibilityHint(OutfitTabCopy.chooseStartingItemHint)
                .accessibilityIdentifier("outfit.empty.chooseStartingItem")
                if hasLoggedToday {
                    Button(OutfitTabCopy.openLoggedToday) {
                        onOpenLoggedToday()
                    }
                    .frame(minHeight: 44)
                }
            }
            .padding()
        }
        .navigationTitle("Outfit")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    ContentView()
}

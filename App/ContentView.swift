import SwiftUI

/// Core-loop shell: Profile → Wardrobe → Detail → Board → Swap → Wear.
struct ContentView: View {
    @StateObject private var model: LoopDemoModel

    init(store: PersistenceStore = InMemoryPersistenceStore.shared) {
        _model = StateObject(wrappedValue: LoopDemoModel(store: store))
    }
    @State private var path = NavigationPath()
    @State private var showSwap = false
    /// F05-04 / GH #53: wardrobe is in Change starting item picker mode.
    @State private var changingAnchor = false
#if DEBUG
    @State private var showDiagnostics = false
#endif
    /// Snapshot of board session until a replacement is committed (or Cancel).
    @State private var outfitBeforeAnchorPick: StubOutfit? = nil

    private enum Route: Hashable {
        case profile
        case review
        case board
        case wearSuccess
        case wear
    }

    var body: some View {
        NavigationStack(path: $path) {
            WardrobeGridView(
                model: model,
                onSelect: { g in
                    model.select(g)
                    path.append(Route.review)
                },
                onBuild: { g in
                    Task { await buildFromWardrobe(g) }
                },
                onOpenProfile: {
                    path.append(Route.profile)
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
                }
            )
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .profile:
                    ProfileDraftView(model: model)
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
                            path = NavigationPath()
                        },
                        onOpenProfile: {
                            path.append(Route.profile)
                        }
                    )
                case .board:
                    OutfitBoardView(
                        model: model,
                        onSwap: { slot in
                            showSwap = true
                            Task { await model.alternatives(for: slot) }
                        },
                        onWear: { path.append(Route.wearSuccess) },
                        onChangeAnchor: {
                            beginAnchorPick()
                        },
                        onChangeWhatIWore: { path.append(Route.wear) }
                    )
                case .wearSuccess:
                    WearSuccessView(
                        model: model,
                        onDone: { path = NavigationPath() },
                        onChangeWhatIWore: { path.append(Route.wear) }
                    )
                case .wear:
                    WearConfirmView(model: model) {
                        path = NavigationPath()
                    }
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
        .task {
            await model.load()
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-demoGrid") || args.contains("-demoFilters") || args.contains("-demoSort") {
                // stay on wardrobe
            } else if args.contains("-demoProfile") {
                path.append(Route.profile)
            } else if args.contains("-demoDetail") {
                if let setMember = model.garments.first(where: { $0.setId != nil && $0.isReady })
                    ?? model.garments.first(where: { model.setFor($0) != nil }) {
                    model.select(setMember)
                }
                path.append(Route.review)
            } else if args.contains("-demoBoard") || args.contains("-demoEngine") {
                model.confirmProfileForDemoIfNeeded()
                if let g = model.selectedGarment { model.select(g) }
                path.append(Route.board)
                await model.buildDemoOutfit()
            } else if args.contains("-demoWear") {
                model.confirmProfileForDemoIfNeeded()
                await model.buildDemoOutfit()
                path.append(Route.board)
                await model.wearingThisFromBoard()
                path.append(Route.wearSuccess)
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
                path.append(Route.board)
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
                path.append(Route.board)
            } else if args.contains("-demoSwap") {
                model.confirmProfileForDemoIfNeeded()
                if let g = model.selectedGarment { model.select(g) }
                await model.buildDemoOutfit()
                path.append(Route.board)
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
                path.append(Route.board)
            } else if args.contains("-demoReview") {
                path.append(Route.review)
            } else if args.contains("-demoFinish") {
                model.confirmProfileForDemoIfNeeded()
                if let draft = model.garments.first(where: { !$0.isReady }) {
                    model.select(draft)
                    path.append(Route.review)
                }
            } else if args.contains("-demoWearHistory") {
                model.confirmProfileForDemoIfNeeded()
                await model.buildDemoOutfit()
                await model.wearingThisFromBoard()
                if let wornId = model.outfit?.assignments.compactMap(\.garmentId).first,
                   let g = model.garments.first(where: { $0.id == wornId }) {
                    model.select(g)
                }
                path.append(Route.review)
            }
        }
        .sheet(isPresented: $showSwap) {
            SwapSheetView(
                model: model,
                onClose: { showSwap = false },
                onChangeStartingItem: {
                    showSwap = false
                    beginAnchorPick()
                },
                onOpenWardrobe: {
                    showSwap = false
                    path = NavigationPath()
                }
            )
        }
        .demoToastHost(model: model)
#if DEBUG
        .sheet(isPresented: $showDiagnostics) {
            DemoDiagnosticsSheet(model: model)
        }
#endif
    }

    private func beginAnchorPick() {
        outfitBeforeAnchorPick = model.outfit
        changingAnchor = true
        // GH #96: reset to wardrobe root so "Choose starting item" chrome is visible.
        // A single pop left the prior Review card on the stack.
        path = NavigationPath()
    }

    private func cancelAnchorPick() {
        if let snap = outfitBeforeAnchorPick {
            model.outfit = snap
        }
        outfitBeforeAnchorPick = nil
        changingAnchor = false
        model.showToast("Returned to your outfit")
        path = NavigationPath()
        path.append(Route.board)
    }

    private func resumeOutfitBoard() {
        guard model.outfit != nil else { return }
        path.append(Route.board)
    }

    private func openLoggedToday() {
        guard model.hasLoggedToday else { return }
        path.append(Route.wearSuccess)
    }

    @MainActor
    private func buildFromWardrobe(_ g: StubGarment) async {
        if changingAnchor {
            let ok = await model.changeAnchor(to: g, priorOutfit: outfitBeforeAnchorPick)
            if ok {
                changingAnchor = false
                outfitBeforeAnchorPick = nil
                // Clean stack: board only (no leftover review cards).
                path = NavigationPath()
                path.append(Route.board)
            }
            // failure: prior restored in model; stay in picker
            return
        }
        model.select(g)
        guard model.validateBuildPreconditions() else { return }
        path.append(Route.board)
        await model.buildDemoOutfit(preserveLocks: true, intent: .firstBuild)
    }

}

#Preview {
    ContentView()
}

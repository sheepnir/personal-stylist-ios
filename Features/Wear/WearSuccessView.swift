import SwiftUI

/// D-75 — first-log confirmation or Logged today summary. Back cannot contradict persist.
struct WearSuccessView: View {
    @ObservedObject var model: LoopDemoModel
    var onDone: () -> Void
    var onChangeWhatIWore: () -> Void

    @State private var checkmarkScale: CGFloat = 0.55
    @State private var checkmarkOpacity: Double = 0
    @State private var undoWindowOpen = true
    @State private var undoHideTask: Task<Void, Never>?
    @State private var showAddPrice = false
    @State private var addPriceGarmentId: UUID?
    @AccessibilityFocusState private var headerFocused: Bool

    private var wornGarments: [StubGarment] {
        model.wornGarmentsForDailyWearDisplay()
    }

    private var cpwPresentation: CostPerWearCopy.WearSuccessPresentation {
        CostPerWearCopy.wearSuccessPresentation(wornGarments: wornGarments) { model.wearCount(for: $0) }
    }

    private var showUndoControl: Bool {
        undoWindowOpen && model.canUndoTodayWear && model.wearFlashToken != nil
    }

    private var showsSuccess: Bool { model.dailyWearShowsSuccessChrome }
    private var showsFailure: Bool { model.dailyWearShowsPersistFailure && !model.hasLoggedToday }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: successSymbol)
                    .font(.system(size: 56))
                    .foregroundStyle(successColor)
                    .scaleEffect(checkmarkScale)
                    .opacity(checkmarkOpacity)
                    .accessibilityHidden(true)

                DailyWearA11yHeading(text: title, identifier: "dailyWear.success.title")
                    .frame(maxWidth: .infinity)
                    .accessibilityFocused($headerFocused)

                if showsFailure {
                    Text(DailyWearCopy.persistFailed)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .accessibilityHint(DailyWearCopy.persistFailedHint)
                        .accessibilityIdentifier("dailyWear.success.persistFailed")
                }

                if showsSuccess, !wornGarments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(wornGarments.prefix(6)) { g in
                                FixtureImageView(garment: g, height: 88, presentation: .tiny)
                                    .frame(width: 88)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .accessibilityLabel(g.displayName)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .accessibilityElement(children: .contain)
                }

                if showsSuccess {
                    cpwSection
                        .padding(.horizontal)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            actionBar
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(showsSuccess || showsFailure)
        .onAppear {
            model.reconcileDailyWearSuccessChrome()
            beginSuccessChrome()
            headerFocused = true
            if showsFailure {
                AccessibilityNotification.Announcement(DailyWearCopy.persistFailed).post()
            }
        }
        .onDisappear {
            undoHideTask?.cancel()
        }
        .sheet(isPresented: $showAddPrice) {
            if let id = addPriceGarmentId {
                AddPriceSheet(model: model, garmentId: id)
            }
        }
    }

    private var title: String {
        if showsFailure { return DailyWearCopy.persistFailed }
        if showsSuccess { return DailyWearCopy.successTitle }
        if model.wearConfirmedMessage == "Wear undone"
            || model.wearConfirmedMessage == "Restored this morning's log"
            || model.wearConfirmedMessage == "Nothing to undo" {
            return DailyWearCopy.undoneTitle
        }
        return DailyWearCopy.successTitle
    }

    private var successSymbol: String {
        if showsFailure { return "exclamationmark.triangle.fill" }
        return showUndoControl || showsSuccess ? "checkmark.circle.fill" : "arrow.uturn.backward.circle"
    }

    private var successColor: Color {
        if showsFailure { return .orange }
        return showUndoControl || showsSuccess ? Color.green : Color.secondary
    }

    private var actionBar: some View {
        VStack(spacing: 8) {
            if showsFailure {
                DailyWearA11yButton(
                    identifier: "dailyWear.success.retry",
                    label: DailyWearCopy.tryAgain,
                    hint: DailyWearCopy.persistFailedHint,
                    action: {
                        Task {
                            let completion = await model.submitDailyWear(garmentIds: nil)
                            if completion == .popToWardrobe {
                                model.clearWearFlash()
                                onDone()
                            }
                        }
                    }
                ) {
                    Text(DailyWearCopy.tryAgain)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                DailyWearA11yButton(
                    identifier: "dailyWear.success.done",
                    label: DailyWearCopy.done,
                    action: {
                        model.clearWearFlash()
                        onDone()
                    }
                ) {
                    Text(DailyWearCopy.done)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilitySortPriority(3)

                if showsSuccess {
                    DailyWearA11yButton(
                        identifier: "dailyWear.success.change",
                        label: DailyWearCopy.changeWhatIWore,
                        hint: DailyWearCopy.submitHintCorrection,
                        action: { onChangeWhatIWore() }
                    ) {
                        Text(DailyWearCopy.changeWhatIWore)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilitySortPriority(2)
                }
            }

            if showUndoControl {
                DailyWearA11yButton(
                    identifier: "dailyWear.success.undo",
                    label: "Undo today’s wear",
                    action: { Task { _ = await model.undoDailyWear() } }
                ) {
                    Text("Undo")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilitySortPriority(1)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    @ViewBuilder
    private var cpwSection: some View {
        if let line = cpwPresentation.pricedLine {
            Text(line)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        } else if let id = cpwPresentation.addPricesGarmentId {
            Button("Add prices to see cost per wear.") {
                addPriceGarmentId = id
                showAddPrice = true
            }
            .font(.footnote.weight(.semibold))
            .multilineTextAlignment(.center)
            .frame(minHeight: 44)
            .accessibilityIdentifier("dailyWear.success.addPrice")
        }
    }

    private func beginSuccessChrome() {
        undoWindowOpen = true
        undoHideTask?.cancel()
        undoHideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            undoWindowOpen = false
        }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
            checkmarkScale = 1
            checkmarkOpacity = 1
        }
    }
}

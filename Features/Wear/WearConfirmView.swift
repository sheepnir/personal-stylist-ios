import SwiftUI

/// D-75 / #103 — What did you wear? New wear vs correction, grouped picker.
struct WearConfirmView: View {
    @ObservedObject var model: LoopDemoModel
    var onFinished: () -> Void = {}

    @State private var selection: Set<UUID>
    @State private var searchText = ""
    @State private var didPreselect: Bool
    @State private var isSubmitting = false

    init(model: LoopDemoModel, onFinished: @escaping () -> Void = {}) {
        self.model = model
        self.onFinished = onFinished
        let seeded = model.dailyWearPreselectedIds()
        _selection = State(initialValue: seeded)
        _didPreselect = State(initialValue: !seeded.isEmpty)
    }

    private var mode: DailyWearMode { model.dailyWearMode }
    private var sections: [DailyWearPickerSection] {
        model.dailyWearPickerSections(search: searchText)
    }
    private var hasReadyPieces: Bool {
        model.visibleGarments.contains(where: model.isEligibleForDailyWear)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if model.dailyWearShowsPersistFailure {
                    Label(DailyWearCopy.persistFailed, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityHint(DailyWearCopy.persistFailedHint)
                        .accessibilityIdentifier("dailyWear.picker.persistFailed")
                }

                Text(mode == .correction ? DailyWearCopy.correctionSubtitle : DailyWearCopy.newWearSubtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if !hasReadyPieces {
                    Text(DailyWearCopy.emptyReady)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                } else if sections.isEmpty {
                    Text(DailyWearCopy.emptySearch)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                } else {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.title)
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                            garmentRows(section.garments)
                        }
                    }
                }

                if hasReadyPieces, selection.isEmpty {
                    Text(DailyWearCopy.emptySelection)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            submitButton
                .padding(.horizontal)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(.bar)
        }
        .navigationTitle(DailyWearCopy.pickerTitle)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: DailyWearCopy.searchPrompt)
        .onAppear {
            if !didPreselect {
                selection = model.dailyWearPreselectedIds()
                didPreselect = true
            }
        }
        .onChange(of: model.dailyWearShowsPersistFailure) { _, failed in
            if failed {
                AccessibilityNotification.Announcement(DailyWearCopy.persistFailed).post()
            }
        }
    }

    private var submitButton: some View {
        let empty = selection.isEmpty
        return DailyWearA11yButton(
            identifier: "dailyWear.picker.submit",
            label: DailyWearCopy.submitAccessibilityLabel(
                isCorrection: mode == .correction,
                selectionEmpty: empty
            ),
            hint: mode == .correction
                ? DailyWearCopy.submitHintCorrection
                : DailyWearCopy.submitHintNew,
            isEnabled: !empty && !isSubmitting,
            action: { Task { @MainActor in await submit() } }
        ) {
            Text(mode == .correction ? DailyWearCopy.updateSelected : DailyWearCopy.logSelected)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    Color.accentColor.opacity(empty || isSubmitting ? 0.4 : 1),
                    in: RoundedRectangle(cornerRadius: 10)
                )
        }
        .disabled(empty || isSubmitting)
        .frame(maxWidth: .infinity)
        }

    @ViewBuilder
    private func garmentRows(_ garments: [StubGarment]) -> some View {
        ForEach(garments) { garment in
            let selected = selection.contains(garment.id)
            DailyWearA11yButton(
                identifier: "dailyWear.picker.row.\(garment.id.uuidString)",
                label: DailyWearCopy.pickerRowLabel(garment),
                value: selected ? DailyWearCopy.selectedValue : DailyWearCopy.notSelectedValue,
                isSelected: selected,
                action: { toggle(garment.id) }
            ) {
                ViewThatFits(in: .horizontal) {
                    pickerRow(garment, selected: selected, stacked: false)
                    pickerRow(garment, selected: selected, stacked: true)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func pickerRow(_ garment: StubGarment, selected: Bool, stacked: Bool) -> some View {
        Group {
            if stacked {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        pickerThumb(garment)
                        pickerMark(selected)
                    }
                    pickerText(garment)
                    AvailabilityBadge(token: garment.availabilityToken)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 12) {
                    pickerThumb(garment)
                    pickerMark(selected)
                    pickerText(garment)
                    Spacer(minLength: 8)
                    AvailabilityBadge(token: garment.availabilityToken)
                }
            }
        }
    }

    private func pickerThumb(_ garment: StubGarment) -> some View {
        FixtureImageView(garment: garment, height: 52, presentation: .tiny)
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
    }

    private func pickerMark(_ selected: Bool) -> some View {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            .accessibilityHidden(true)
    }

    private func pickerText(_ garment: StubGarment) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(garment.displayName)
                .font(.body.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(garment.slot.displayLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func toggle(_ id: UUID) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    @MainActor
    private func submit() async {
        guard !selection.isEmpty, !isSubmitting else { return }
        isSubmitting = true
        let completion = await model.submitDailyWear(garmentIds: Array(selection))
        isSubmitting = false
        if completion == .popToWardrobe {
            onFinished()
        }
    }
}

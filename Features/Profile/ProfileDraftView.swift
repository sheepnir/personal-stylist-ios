import SwiftUI

/// Editable style profile — all PRD §7.1 fields, autosave on Back (D-45 / #124).
/// Welcome + privacy remain HELD this wave.
struct ProfileDraftView: View {
    static let deviceAccessSectionID = "device-access-section"

    @ObservedObject var model: LoopDemoModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    @State private var ageText: String = ""
    @State private var profession: String = ""
    @State private var workEnvironment: String = ""
    @State private var typicalWeek: Set<String> = []
    @State private var typicalWeekExtra: String = ""
    @State private var selectedGoals: Set<String> = []
    @State private var goalsExtra: String = ""
    @State private var selectedConstraints: Set<String> = []
    @State private var constraintsExtra: String = ""
    @State private var experimentation: Double = 3
    @State private var summaryText: String = ""
    @State private var isDirty = false
    @State private var didConfirmThisVisit = false
    @State private var showResetConfirm = false
    @State private var showClearConfirm = false
    @State private var isDataControlBusy = false

    var body: some View {
        ScrollViewReader { proxy in
        Form {
            if let profile = model.styleProfile {
                Section {
                    Label(
                        profile.isDraft ? "Draft — confirm to unlock outfit builds" : "Confirmed",
                        systemImage: profile.isDraft ? "pencil.circle" : "checkmark.seal.fill"
                    )
                    .foregroundStyle(profile.isDraft ? Color.orange : Color.green)
                    if profile.seedSource != nil {
                        Text("Pre-filled from your notes — edit anything.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Essentials") {
                    TextField("Age", text: $ageText)
                        .keyboardType(.numberPad)
                        .accessibilityLabel("Age")
                        .onChange(of: ageText) { _, _ in isDirty = true }
                    LabeledContent("Profession") {
                        TextField("Profession", text: $profession)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel("Profession")
                    }
                    .onChange(of: profession) { _, _ in isDirty = true }

                    Picker("Work environment", selection: $workEnvironment) {
                        Text("Not set").tag("")
                        ForEach(ProfileFieldCopy.workEnvironments) { option in
                            Text(option.label).tag(option.id)
                        }
                    }
                    .accessibilityLabel("Work environment")
                    .onChange(of: workEnvironment) { _, _ in isDirty = true }
                }

                Section {
                    chipWrap(ProfileFieldCopy.typicalWeekChips, selected: $typicalWeek)
                    TextField("Anything else about a typical week", text: $typicalWeekExtra, axis: .vertical)
                        .lineLimit(2...4)
                        .accessibilityLabel("Typical week notes")
                } header: {
                    Text("Typical week")
                } footer: {
                    Text("Pick the days that show up most. No percentages needed.")
                }
                .onChange(of: typicalWeek) { _, _ in isDirty = true }
                .onChange(of: typicalWeekExtra) { _, _ in isDirty = true }

                Section {
                    chipWrap(ProfileFieldCopy.goalOptions, selected: $selectedGoals)
                    TextField("Another goal (optional)", text: $goalsExtra, axis: .vertical)
                        .lineLimit(2...4)
                        .accessibilityLabel("Additional goal")
                } header: {
                    Text("Goals")
                }
                .onChange(of: selectedGoals) { _, _ in isDirty = true }
                .onChange(of: goalsExtra) { _, _ in isDirty = true }

                Section {
                    chipWrap(ProfileFieldCopy.constraintChips, selected: $selectedConstraints)
                    TextField("Comfort / never rules", text: $constraintsExtra, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityLabel("Constraints")
                } header: {
                    Text("Constraints")
                }
                .onChange(of: selectedConstraints) { _, _ in isDirty = true }
                .onChange(of: constraintsExtra) { _, _ in isDirty = true }

                Section {
                    Slider(value: $experimentation, in: 1...5, step: 1)
                        .accessibilityLabel("Experimentation")
                        .accessibilityValue(experimentationLabel)
                    HStack {
                        Text("Keep me in my lane")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Surprise me")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(experimentationLabel)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Experimentation")
                }
                .onChange(of: experimentation) { _, _ in isDirty = true }

                Section {
                    TextEditor(text: $summaryText)
                        .frame(minHeight: 120)
                        .accessibilityLabel("Summary")
                    Text("Edit freely — your text becomes user-owned. Unanswered topics stay out of the summary.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Summary")
                }
                .onChange(of: summaryText) { _, _ in isDirty = true }

                Section {
                    Button(profile.isDraft ? "Confirm profile" : "Save changes") {
                        saveEdits(confirm: profile.isDraft)
                        if profile.isDraft {
                            didConfirmThisVisit = true
                            dismiss()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel(profile.isDraft ? "Confirm profile" : "Save changes")
                }

            }

            Section {
                Button(DataControlsCopy.resetProfileAction, role: .destructive) {
                    showResetConfirm = true
                }
                .disabled(isDataControlBusy)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .accessibilityLabel(DataControlsCopy.resetProfileAction)
                .accessibilityHint("Clears answers, summary, and confirmation. Wardrobe stays.")
            } header: {
                Text("Profile")
            }

            Section {
                Button(DataControlsCopy.clearWardrobeAction, role: .destructive) {
                    showClearConfirm = true
                }
                .disabled(isDataControlBusy)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .accessibilityLabel(DataControlsCopy.clearWardrobeAction)
                .accessibilityHint("Removes all garments, photos, looks, and their wear history.")
            } header: {
                Text("Data")
            }

            // TestFlight / Release device-token seed (#89 / D-46). No default secrets.
            DeviceAccessSection(model: model)
        }
        .onChange(of: model.scrollToDeviceAccessRequested) { _, requested in
            guard requested else { return }
            if accessibilityReduceMotion {
                proxy.scrollTo(Self.deviceAccessSectionID, anchor: .top)
            } else {
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(Self.deviceAccessSectionID, anchor: .top)
                }
            }
            model.scrollToDeviceAccessRequested = false
        }
        }
        .navigationTitle("Style profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task {
                if model.styleProfile == nil {
                    await model.ensureEditableStyleProfile()
                }
                hydrate()
            }
        }
        .onChange(of: model.styleProfile?.id) { _, _ in hydrate() }
        .onDisappear {
            if isDirty && !didConfirmThisVisit {
                saveEdits(confirm: false)
            }
        }
        .confirmationDialog(
            DataControlsCopy.resetProfileTitle,
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button(DataControlsCopy.resetProfileAction, role: .destructive) {
                Task { await resetConfirmedProfile() }
            }
            .accessibilityLabel(DataControlsCopy.resetProfileAction)
            Button(DataControlsCopy.cancel, role: .cancel) {}
        } message: {
            Text(DataControlsCopy.resetProfileMessage)
        }
        .confirmationDialog(
            DataControlsCopy.clearWardrobeTitle,
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button(DataControlsCopy.clearWardrobeAction, role: .destructive) {
                Task { await clearConfirmedWardrobe() }
            }
            .accessibilityLabel(DataControlsCopy.clearWardrobeAction)
            Button(DataControlsCopy.cancel, role: .cancel) {}
        } message: {
            Text(DataControlsCopy.clearWardrobeMessage)
        }
    }

    @MainActor
    private func resetConfirmedProfile() async {
        isDataControlBusy = true
        defer { isDataControlBusy = false }
        await model.resetActiveStyleProfile()
        hydrate()
    }

    @MainActor
    private func clearConfirmedWardrobe() async {
        isDataControlBusy = true
        defer { isDataControlBusy = false }
        await model.clearWardrobeAndLooks()
    }

    private func chipWrap(_ options: [String], selected: Binding<Set<String>>) -> some View {
        FlexibleChipWrap(options: options, selected: selected)
    }

    private var experimentationLabel: String {
        switch Int(experimentation) {
        case 1: return "Keep me in my lane"
        case 2: return "Mostly familiar"
        case 3: return "Slight stretch"
        case 4: return "Push me a bit"
        default: return "Surprise me"
        }
    }

    private func hydrate() {
        guard let p = model.styleProfile else { return }
        ageText = p.age.map(String.init) ?? ""
        profession = p.profession ?? ""
        workEnvironment = p.workEnvironment ?? ""
        let week = ProfileFieldCopy.parseTypicalWeek(p.typicalWeekNotes)
        typicalWeek = week.selected
        typicalWeekExtra = week.extra
        let goals = ProfileFieldCopy.splitGoals(p.goals)
        selectedGoals = goals.selected
        goalsExtra = goals.extra
        let constraints = ProfileFieldCopy.splitConstraints(p.constraintsNotes)
        selectedConstraints = constraints.selected
        constraintsExtra = constraints.extra
        experimentation = Double(p.experimentationLevel ?? 3)
        summaryText = p.summary ?? ""
        isDirty = false
        didConfirmThisVisit = false
    }

    private func saveEdits(confirm: Bool) {
        guard var p = model.styleProfile else { return }
        let trimmedAge = ageText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedAge.isEmpty {
            p.age = nil
        } else if let age = Int(trimmedAge), age > 0, age < 120 {
            p.age = age
        }
        p.profession = profession.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.workEnvironment = workEnvironment.isEmpty ? nil : workEnvironment
        p.workEnvironmentLabel = ProfileFieldCopy.workEnvironmentLabel(for: p.workEnvironment)
        p.typicalWeekNotes = ProfileFieldCopy.encodeTypicalWeek(selected: typicalWeek, extra: typicalWeekExtra)
        p.goals = ProfileFieldCopy.encodeGoals(selected: selectedGoals, extra: goalsExtra)
        p.constraintsNotes = ProfileFieldCopy.encodeConstraints(selected: selectedConstraints, extra: constraintsExtra)
        p.experimentationLevel = Int(experimentation)
        if summaryText != (p.summary ?? "") {
            p.summary = summaryText
            p.summaryUserOwned = true
        }
        isDirty = false
        if confirm {
            model.confirmProfile(p)
        } else {
            if p.isConfirmed {
                p.version += 1
            }
            model.updateProfile(p)
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Simple wrapping chip row for profile multi-selects.
private struct FlexibleChipWrap: View {
    let options: [String]
    @Binding var selected: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(options, id: \.self) { option in
                let isOn = selected.contains(option)
                Button {
                    if isOn { selected.remove(option) } else { selected.insert(option) }
                } label: {
                    HStack {
                        Text(option.prefix(1).uppercased() + option.dropFirst())
                            .font(.subheadline.weight(isOn ? .medium : .regular))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        if isOn {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(isOn ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .accessibilityLabel(option)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

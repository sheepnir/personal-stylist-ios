import SwiftUI

/// Finish details — colour grid, all readiness fields, bottom Save bar, next-draft queue (#123).
/// Edit garment reuses this sheet (`FinishDetailsMode.editGarment`) — no second editor (D-72 / #120).
/// Camera intake (`FinishDetailsMode.cameraIntake`) reuses it with an explicit slot (D-73).
struct FinishDetailsSheet: View {
    @ObservedObject var model: LoopDemoModel
    let garmentId: UUID
    let mode: FinishDetailsMode
    var cameraPending: CameraPending? = nil
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editingId: UUID
    @State private var selectedSlot: StubSlot = .top
    @State private var cameraSlot: StubSlot? = nil
    @State private var name: String = ""
    @State private var colorFamilyId: String = ""
    @State private var colorHex: String = ""
    @State private var colorDisplayName: String = ""
    @State private var pattern: String = ""
    @State private var surface: String = ""
    @State private var formality: Int? = nil
    @State private var warmth: Int? = nil
    @State private var priceText: String = ""
    @State private var currency: String = CostPerWearCopy.deviceCurrency
    @State private var includePurchaseDate = false
    @State private var purchaseDate = Date()
    @State private var priorWearBucket: String = ""
    @State private var isSaving = false
    @State private var errorText: String?
    @State private var remainingAfterSave: Int = 0
    @State private var seededSnapshot: FinishDetailsSnapshot?
    @State private var showDiscardConfirm = false
    @State private var didCommitCamera = false

    private let patternOptions: [(id: String, label: String)] = [
        ("SOLID", "Solid"), ("STRIPE", "Stripe"), ("CHECK", "Check"),
        ("PLAID", "Plaid"), ("HERRINGBONE", "Herringbone"), ("PRINT", "Print"), ("TEXTURED_SOLID", "Textured solid"),
    ]
    private let surfaceOptions: [(id: String, label: String, help: String?)] = [
        ("SMOOTH", "Smooth", "Glass-like finish (silk, satin, polished cotton)"),
        ("MATTE", "Matte", "Flat, non-shiny (standard cotton, linen)"),
        ("TEXTURED", "Textured", "Visible weave or texture (knits, basket weave)"),
        ("NAPPED", "Napped", "Soft, fuzzy surface (flannel, fleece, brushed cotton)"),
        ("RUGGED", "Rugged", "Coarse, sturdy texture (denim, canvas, tweed)"),
    ]
    private let formalityLabels = [1: "Very casual", 2: "Casual", 3: "Smart casual", 4: "Business", 5: "Formal"]
    private let warmthLabels = [1: "Very light", 2: "Light", 3: "Medium", 4: "Warm", 5: "Very warm"]

    init(
        model: LoopDemoModel,
        garmentId: UUID,
        mode: FinishDetailsMode = .finishDetails,
        cameraPending: CameraPending? = nil,
        onSaved: @escaping () -> Void
    ) {
        self.model = model
        self.garmentId = garmentId
        self.mode = mode
        self.cameraPending = cameraPending
        self.onSaved = onSaved
        _editingId = State(initialValue: cameraPending?.id ?? garmentId)
    }

    private var resolvedSlot: StubSlot? {
        mode == .cameraIntake ? cameraSlot : selectedSlot
    }

    private var garment: StubGarment? {
        if mode == .cameraIntake, let cameraPending {
            return cameraPending.previewGarment(displayName: liveDisplayName, slot: cameraSlot)
        }
        return model.garments.first(where: { $0.id == editingId })
    }

    private var remainingDraftIds: [UUID] {
        model.visibleGarments.filter { !$0.isReady && $0.id != editingId }.map(\.id)
    }

    private var liveDisplayName: String {
        if mode == .cameraIntake {
            return CameraIntakeDraft.liveDisplayName(name: name, slot: cameraSlot)
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return StubGarment.untitledName(for: selectedSlot)
    }

    private var finishDetailsTitle: String {
        guard garment != nil else { return "Finish details" }
        if liveDisplayName.lowercased().hasPrefix("untitled") {
            return "Finish details"
        }
        return liveDisplayName
    }

    private var titleText: String {
        GarmentEditCopy.navigationTitle(mode: mode, finishDetailsTitle: finishDetailsTitle)
    }

    private var currentSnapshot: FinishDetailsSnapshot {
        FinishDetailsSnapshot(
            slot: resolvedSlot ?? selectedSlot,
            name: name,
            colorFamilyId: colorFamilyId,
            colorHex: colorHex,
            colorDisplayName: colorDisplayName,
            pattern: pattern,
            surface: surface,
            formality: formality,
            warmth: warmth,
            priceText: priceText,
            currency: currency,
            includePurchaseDate: includePurchaseDate,
            purchaseDate: purchaseDate,
            priorWearBucket: priorWearBucket
        )
    }

    private var isDirty: Bool {
        guard let seededSnapshot else { return false }
        return FinishDetailsDraft.isDirty(seeded: seededSnapshot, current: currentSnapshot)
    }

    private var slotDiffersFromSaved: Bool {
        guard mode != .cameraIntake, let garment else { return false }
        return FinishDetailsDraft.showsSlotChangeFootnote(selected: selectedSlot, saved: garment.slot)
    }

    private var primarySaveTitle: String {
        GarmentEditCopy.primarySaveTitle(mode: mode)
    }

    private var nameIsUserSet: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        if mode == .cameraIntake { return true }
        if garment?.displayNameSource == "USER" { return true }
        return trimmed != (garment?.displayName ?? "")
    }

    private var colorState: FinishDetailsColorState {
        FinishDetailsColorState(
            familyId: colorFamilyId,
            hex: colorHex,
            displayName: colorDisplayName
        )
    }

    private var missingRequiredFields: [String] {
        var missing: [String] = []
        if FinishDetailsColorDraft.missingColor(colorState) { missing.append("Color") }
        if pattern.isEmpty { missing.append("Pattern") }
        if surface.isEmpty { missing.append("Surface") }
        if formality == nil { missing.append("Formality") }
        if warmth == nil { missing.append("Warmth") }
        return missing
    }

    private var hasRequiredSlot: Bool {
        !FinishDetailsDraft.requiresExplicitSlot(mode: mode) || CameraIntakeDraft.isSlotChosen(cameraSlot)
    }

    private var canMarkReady: Bool { garment != nil && missingRequiredFields.isEmpty && hasRequiredSlot }
    private var canSaveDraft: Bool { garment != nil && hasRequiredSlot }

    var body: some View {
        NavigationStack {
            Form {
                if let g = garment {
                    if FinishDetailsDraft.placesNameAndCategoryFirst(mode: mode) {
                        identitySection
                        headerSection(g)
                    } else {
                        headerSection(g)
                        identitySection
                    }
                    colorSection
                    pickerSection("Pattern", selection: $pattern, options: patternOptions.map { ($0.id, $0.label) }, empty: pattern.isEmpty)
                    surfaceSection
                    levelSection("Formality", selection: $formality, labels: formalityLabels, empty: formality == nil)
                    levelSection("Warmth", selection: $warmth, labels: warmthLabels, empty: warmth == nil, footer: "Warmth = how much this keeps you warm (1 = very light, 5 = very warm)")
                    DisclosureGroup("More details") {
                        GarmentPriceAmountFields(priceText: $priceText, currency: $currency)
                        GarmentPriceOptionalFields(
                            includePurchaseDate: $includePurchaseDate,
                            purchaseDate: $purchaseDate,
                            priorWearBucket: $priorWearBucket
                        )
                    }
                    if !canMarkReady {
                        Section {
                            Text(GarmentEditCopy.requiredFieldsLine(missingRequiredFields))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel(GarmentEditCopy.requiredFieldsLine(missingRequiredFields))
                        }
                    }
                    if FinishDetailsDraft.showsNextDraftQueue(mode: mode), remainingAfterSave > 0 {
                        Section {
                            Text("\(remainingAfterSave) draft\(remainingAfterSave == 1 ? "" : "s") left in this queue.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Section {
                        Text(sheetFootnote)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let errorText {
                        Section {
                            Text(errorText)
                                .foregroundStyle(.red)
                                .font(.footnote)
                        }
                    }
                } else {
                    ContentUnavailableView("Garment missing", systemImage: "tshirt")
                }
            }
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(GarmentEditCopy.cancel) {
                        requestDismiss()
                    }
                    .accessibilityLabel(GarmentEditCopy.cancel)
                }
            }
            .confirmationDialog(
                GarmentEditCopy.discardTitle,
                isPresented: $showDiscardConfirm,
                titleVisibility: .visible
            ) {
                Button(GarmentEditCopy.discardAction, role: .destructive) {
                    dismiss()
                }
                .accessibilityLabel(GarmentEditCopy.discardAction)
                Button(GarmentEditCopy.keepEditing, role: .cancel) {}
                    .accessibilityLabel(GarmentEditCopy.keepEditing)
            } message: {
                Text(GarmentEditCopy.discardMessage)
            }
            .safeAreaInset(edge: .bottom) {
                if garment != nil {
                    saveBar
                }
            }
            .interactiveDismissDisabled(FinishDetailsDraft.blocksInteractiveDismiss(isDirty: isDirty, isSaving: isSaving))
            .onAppear { seedFromGarment() }
            .onChange(of: editingId) { _, _ in seedFromGarment() }
            .onChange(of: errorText) { _, text in
                if let text {
                    AccessibilityNotification.Announcement(text).post()
                }
            }
            .onDisappear {
                if mode == .cameraIntake, !didCommitCamera, let id = cameraPending?.id {
                    Task { await model.abandonCameraPending(id: id) }
                }
            }
        }
    }

    private func headerSection(_ g: StubGarment) -> some View {
        Section {
            HStack(spacing: 12) {
                FixtureImageView(garment: headerPreviewGarment(g), height: 64, presentation: .tiny)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(liveDisplayName)
                        .font(.headline)
                    Text(resolvedSlot?.displayLabel ?? CameraIntakeCopy.selectSlot)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Photo stays as-is")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var identitySection: some View {
        Section {
            if FinishDetailsDraft.placesNameAndCategoryFirst(mode: mode) {
                nameField
                slotPicker
            } else {
                slotPicker
                nameField
            }
        } header: {
            Text(GarmentEditCopy.identitySectionHeader(mode: mode))
        } footer: {
            Text(identityFooter)
        }
    }

    private var nameField: some View {
        TextField(GarmentEditCopy.nameField, text: $name)
            .textInputAutocapitalization(.words)
            .accessibilityLabel(GarmentEditCopy.nameAccessibility)
    }

    @ViewBuilder
    private var slotPicker: some View {
        if mode == .cameraIntake {
            Picker(GarmentEditCopy.slotLabel, selection: $cameraSlot) {
                Text(CameraIntakeCopy.selectSlot).tag(Optional<StubSlot>.none)
                ForEach(StubSlot.allCases, id: \.self) { slot in
                    Text(slot.displayLabel).tag(Optional(slot))
                }
            }
            .accessibilityLabel(GarmentEditCopy.slotLabel)
        } else {
            Picker(GarmentEditCopy.slotLabel, selection: $selectedSlot) {
                ForEach(StubSlot.allCases, id: \.self) { slot in
                    Text(slot.displayLabel).tag(slot)
                }
            }
            .accessibilityLabel(GarmentEditCopy.slotLabel)
        }
    }

    private var identityFooter: String {
        let untitledHint: String
        if mode == .cameraIntake, cameraSlot == nil {
            untitledHint = "Name updates as you type. Leave blank for “Untitled” after you choose a slot. A name you set is never overwritten."
        } else {
            untitledHint = "Name updates as you type. Leave blank for “Untitled \(resolvedSlot?.displayLabel ?? CameraIntakeCopy.selectSlot)”. A name you set is never overwritten."
        }
        if mode == .editGarment, slotDiffersFromSaved {
            return untitledHint + "\n\n" + GarmentEditCopy.slotChangeFootnote
        }
        return untitledHint
    }

    private var sheetFootnote: String {
        switch mode {
        case .editGarment:
            return GarmentEditCopy.editSheetFootnote
        case .cameraIntake:
            return CameraIntakeCopy.cameraSheetFootnote
        case .finishDetails:
            return "This piece is already in the wardrobe. Cancel leaves it as-is. Save marks it ready to use. Save as draft stays out of outfit generation until every required field is set."
        }
    }

    private var colorSection: some View {
        Section {
            if colorState.isCustom {
                FinishDetailsCustomColorRow(state: colorState)
            }
            colorGrid(ColorFamilyCatalog.primary)
            DisclosureGroup {
                colorGrid(ColorFamilyCatalog.more)
            } label: {
                Text("More colours")
            }
            .accessibilityIdentifier("finish.details.color.more")
            TextField("Color name (optional)", text: $colorDisplayName)
                .textInputAutocapitalization(.words)
                .accessibilityLabel("Color name")
        } header: {
            Text(FinishDetailsColorDraft.missingColor(colorState) ? "Color *" : "Color")
        }
    }

    private func colorGrid(_ options: [ColorFamilyOption]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 8)], spacing: 8) {
            ForEach(options) { option in
                let selected = colorFamilyId == option.id
                Button {
                    applyColorState(FinishDetailsColorDraft.selectingCatalog(option))
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            if option.isSplit {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(hex: option.hex) ?? .gray, Color.white.opacity(0.7)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            } else {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(hex: option.hex) ?? .gray)
                            }
                            if selected {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(option.id == "white" || option.id == "cream" || option.id == "yellow" ? Color.black : Color.white)
                            }
                        }
                        .frame(height: 36)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(selected ? Color.primary : Color.secondary.opacity(0.35), lineWidth: selected ? 2 : 1)
                        )
                        Text(option.label)
                            .font(.caption2)
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                    }
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .accessibilityLabel(option.label)
                .accessibilityValue(selected ? GarmentEditCopy.selectedValue : GarmentEditCopy.notSelectedValue)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("finish.details.color.\(option.id)")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    private func applyColorState(_ state: FinishDetailsColorState) {
        colorFamilyId = state.familyId
        colorHex = state.hex
        colorDisplayName = state.displayName
    }

    private func pickerSection(
        _ title: String,
        selection: Binding<String>,
        options: [(String, String)],
        empty: Bool
    ) -> some View {
        Section {
            Picker(title, selection: selection) {
                Text("Select…").tag("")
                ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
            }
        } header: {
            Text(empty ? "\(title) *" : title)
        }
    }

    private var surfaceSection: some View {
        Section {
            Picker("Surface", selection: $surface) {
                Text("Select…").tag("")
                ForEach(surfaceOptions, id: \.id) { Text($0.label).tag($0.id) }
            }
            if let selectedSurface = surfaceOptions.first(where: { $0.id == surface }),
               let help = selectedSurface.help {
                Text(help)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(surface.isEmpty ? "Surface *" : "Surface")
        }
    }

    private func levelSection(
        _ title: String,
        selection: Binding<Int?>,
        labels: [Int: String],
        empty: Bool,
        footer: String? = nil
    ) -> some View {
        Section {
            Picker(title, selection: selection) {
                Text("Select…").tag(Optional<Int>.none)
                ForEach(1...5, id: \.self) { n in
                    Text(labels[n] ?? "\(n)").tag(Optional(n))
                }
            }
        } header: {
            Text(empty ? "\(title) *" : title)
        } footer: {
            if let footer {
                Text(footer).font(.caption)
            }
        }
    }

    private var saveBar: some View {
        FinishDetailsSaveBar(
            primaryTitle: primarySaveTitle,
            canMarkReady: canMarkReady,
            canSaveDraft: canSaveDraft,
            isSaving: isSaving,
            remainingDraftCount: remainingDraftIds.count,
            showsNextDraftQueue: FinishDetailsDraft.showsNextDraftQueue(mode: mode),
            saveHint: GarmentEditCopy.saveAccessibilityHint(
                canMarkReady: canMarkReady,
                isSaving: isSaving,
                missingRequiredFields: missingRequiredFields,
                hasRequiredSlot: hasRequiredSlot
            ),
            saveAsDraftHint: GarmentEditCopy.saveAsDraftAccessibilityHint(
                canSaveDraft: canSaveDraft,
                isSaving: isSaving,
                hasRequiredSlot: hasRequiredSlot
            ),
            onSaveReady: { Task { _ = await saveDetails(markReady: true) } },
            onSaveDraft: { Task { _ = await saveDetails(markReady: false) } },
            onNextDraft: {
                Task {
                    if await saveDetails(markReady: false) {
                        advanceToNextDraft()
                    }
                }
            }
        )
    }

    private func headerPreviewGarment(_ g: StubGarment) -> StubGarment {
        var preview = g
        preview.displayName = liveDisplayName
        preview.slot = resolvedSlot ?? g.slot
        if let previewColor = FinishDetailsColorDraft.previewColor(from: colorState) {
            preview.colorPrimary = previewColor
        }
        return preview
    }

    private func seedFromGarment() {
        guard let g = garment else { return }
        remainingAfterSave = remainingDraftIds.count
        if mode == .cameraIntake {
            cameraSlot = CameraIntakeDraft.defaultSlotForCameraIntake()
        } else {
            selectedSlot = g.slot
        }
        if g.displayNameSource == "USER" {
            name = g.displayName
        } else if g.displayName.lowercased().hasPrefix("untitled") {
            name = ""
        } else {
            name = g.displayName
        }
        applyColorState(FinishDetailsColorDraft.seed(from: g.colorPrimary))
        pattern = g.pattern ?? ""
        surface = g.surface ?? ""
        formality = g.formality
        warmth = g.warmth
        if let price = g.purchasePrice, price > 0 {
            priceText = NSDecimalNumber(decimal: price).stringValue
        } else {
            priceText = ""
        }
        currency = g.purchaseCurrency ?? CostPerWearCopy.deviceCurrency
        if let date = g.purchaseDate {
            includePurchaseDate = true
            purchaseDate = date
        } else {
            includePurchaseDate = false
        }
        priorWearBucket = g.priorWearBucket ?? ""
        errorText = nil
        seededSnapshot = FinishDetailsSnapshot(
            slot: resolvedSlot ?? selectedSlot,
            name: name,
            colorFamilyId: colorFamilyId,
            colorHex: colorHex,
            colorDisplayName: colorDisplayName,
            pattern: pattern,
            surface: surface,
            formality: formality,
            warmth: warmth,
            priceText: priceText,
            currency: currency,
            includePurchaseDate: includePurchaseDate,
            purchaseDate: purchaseDate,
            priorWearBucket: priorWearBucket
        )
    }

    private func requestDismiss() {
        if FinishDetailsDraft.shouldConfirmDismiss(isDirty: isDirty) {
            showDiscardConfirm = true
        } else {
            dismiss()
        }
    }

    private func advanceToNextDraft() {
        guard let next = remainingDraftIds.first else { return }
        editingId = next
    }

    @MainActor
    private func saveDetails(markReady: Bool) async -> Bool {
        guard let g = garment else { return false }
        isSaving = true
        errorText = nil
        defer { isSaving = false }

        let parsedPrice = CostPerWearCopy.parsePrice(priceText)
        if !priceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, parsedPrice == nil {
            errorText = "Enter a price greater than 0, or leave it blank."
            return false
        }

        let color = FinishDetailsColorDraft.persistColor(from: colorState)

        if mode == .cameraIntake {
            guard let slot = cameraSlot, let pending = cameraPending else {
                errorText = CameraIntakeCopy.slotRequired
                return false
            }
            let ok = await model.commitCameraPending(
                id: pending.id,
                fields: CameraIntakeCommitFields(
                    slot: slot,
                    displayName: liveDisplayName,
                    displayNameIsUserSet: nameIsUserSet,
                    color: color,
                    pattern: pattern,
                    surface: surface,
                    formality: formality,
                    warmth: warmth,
                    purchasePrice: parsedPrice,
                    purchaseCurrency: parsedPrice == nil ? nil : currency,
                    purchaseDate: includePurchaseDate ? purchaseDate : nil,
                    priorWearBucket: priorWearBucket.isEmpty ? nil : priorWearBucket,
                    markReady: markReady
                )
            )
            if ok {
                didCommitCamera = true
                onSaved()
                dismiss()
                return true
            }
            errorText = CameraIntakeCopy.saveFailed
            return false
        }

        let ok = await model.completeReadiness(
            id: g.id,
            slot: selectedSlot,
            displayName: liveDisplayName,
            displayNameIsUserSet: nameIsUserSet,
            color: color,
            pattern: pattern,
            surface: surface,
            formality: formality,
            warmth: warmth,
            purchasePrice: parsedPrice,
            purchaseCurrency: parsedPrice == nil ? nil : currency,
            purchaseDate: includePurchaseDate ? purchaseDate : nil,
            priorWearBucket: priorWearBucket.isEmpty ? nil : priorWearBucket,
            applyPurchase: true,
            requireComplete: markReady
        )
        if ok {
            if FinishDetailsDraft.dismissesAfterSuccessfulSave(mode: mode) {
                onSaved()
                dismiss()
                return true
            }
            let leftover = remainingDraftIds
            remainingAfterSave = leftover.count
            if markReady, let next = leftover.first {
                editingId = next
            } else if markReady {
                onSaved()
                dismiss()
            } else {
                seedFromGarment()
            }
            return true
        } else {
            errorText = markReady
                ? "Fill every required field to mark ready."
                : "Couldn’t save — try again."
            return false
        }
    }
}

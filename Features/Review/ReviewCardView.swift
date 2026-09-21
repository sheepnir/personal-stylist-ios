import SwiftUI

/// M1-F03-04 garment detail (Review route) — availability, set membership, Build CTA.
struct ReviewCardView: View {
    @ObservedObject var model: LoopDemoModel
    var onBuild: () -> Void
    var onFinishedDetails: (() -> Void)? = nil
    var onOpenProfile: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.persistenceStore) private var persistenceStore
    @StateObject private var photoReplaceSession = PhotoReplaceSession()
    @State private var finishDetailsPresentation: FinishDetailsPresentation?
    @State private var showAddPrice = false
    @State private var showDeleteConfirm = false
    @State private var showPhotoReplaceSource = false
    @AccessibilityFocusState private var changePhotoFocused: Bool

    var body: some View {
        PhotoReplaceHost(session: photoReplaceSession) {
            detailScroll
        }
        .onAppear {
            photoReplaceSession.attach(model, store: persistenceStore)
        }
        .onChange(of: photoReplaceSession.state.commitInFlight) { wasInFlight, inFlight in
            if wasInFlight && !inFlight && photoReplaceSession.state.alert == nil {
                changePhotoFocused = true
            }
        }
        .onChange(of: photoReplaceSession.state.cover) { oldCover, newCover in
            if oldCover != nil && newCover == nil
                && !photoReplaceSession.state.commitInFlight
                && photoReplaceSession.state.alert == nil {
                changePhotoFocused = true
            }
        }
    }

    private var detailScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if model.isOffline {
                    offlineBanner
                }
                if let g = liveGarment {
                    hero(g)
                    titleRow(g)
                    if g.readiness == .draft {
                        draftBanner
                    }
                    availabilityControl(g)
                    primaryCTA(g)
                    attributes(g)
                    setMembership(g)
                    wearAndCPW(g)
                    WearHistorySection(model: model, garmentId: g.id)
                } else {
                    ContentUnavailableView(
                        "No garment",
                        systemImage: "tshirt",
                        description: Text("This piece is no longer in your wardrobe.")
                    )
                }
            }
            .padding()
        }
        .navigationTitle(liveGarment?.displayName ?? "Detail")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if liveGarment != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(WearHistoryCopy.editAction) {
                        if let id = liveGarment?.id {
                            finishDetailsPresentation = .edit(garmentId: id)
                        }
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityLabel(WearHistoryCopy.editAccessibility)
                    .accessibilityHint(WearHistoryCopy.editHint)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let g = liveGarment {
                        Menu {
                            ForEach(AvailabilityToken.allCases, id: \.self) { token in
                                Button {
                                    model.setAvailability(g.id, token.rawValue)
                                } label: {
                                    Label(token.accessibilityName, systemImage: token.symbolName)
                                }
                            }
                        } label: {
                            Label("Change availability", systemImage: "arrow.triangle.2.circlepath")
                        }
                        Divider()
                        Button(DataControlsCopy.deleteGarmentAction, role: .destructive) {
                            showDeleteConfirm = true
                        }
                        .accessibilityLabel(DataControlsCopy.deleteGarmentAction)
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("More")
                .accessibilityHint("Availability and delete garment")
            }
        }
        .confirmationDialog(
            DataControlsCopy.deleteGarmentTitle,
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(DataControlsCopy.deleteGarmentAction, role: .destructive) {
                Task { await deleteConfirmedGarment() }
            }
            .accessibilityLabel(DataControlsCopy.deleteGarmentAction)
            Button(DataControlsCopy.cancel, role: .cancel) {}
        } message: {
            Text(DataControlsCopy.deleteGarmentMessage(name: liveGarment?.displayName ?? ""))
        }
        .sheet(item: $finishDetailsPresentation) { presentation in
            FinishDetailsSheet(model: model, garmentId: presentation.garmentId, mode: presentation.mode) {
                onFinishedDetails?()
            }
        }
        .sheet(isPresented: $showAddPrice) {
            if let id = liveGarment?.id {
                AddPriceSheet(model: model, garmentId: id)
            }
        }
        .confirmationDialog(
            PhotoReplaceCopy.changePhoto,
            isPresented: $showPhotoReplaceSource,
            titleVisibility: .visible
        ) {
            Button(PhotoReplaceCopy.chooseFromPhotos) {
                guard let id = liveGarment?.id else { return }
                photoReplaceSession.attach(model, store: persistenceStore)
                photoReplaceSession.apply(.chooseSource(.photos, garmentId: id))
            }
            .accessibilityLabel(PhotoReplaceCopy.chooseFromPhotos)
            .accessibilityHint(PhotoReplaceCopy.chooseFromPhotosHint)
            .accessibilityAddTraits(.isButton)
            Button(PhotoReplaceCopy.takePhoto) {
                handleTakePhotoReplace()
            }
            .accessibilityLabel(PhotoReplaceCopy.takePhoto)
            .accessibilityHint(PhotoReplaceCopy.takePhotoHint)
            .accessibilityAddTraits(.isButton)
            Button(PhotoReplaceCopy.cancel, role: .cancel) {}
            .accessibilityLabel(PhotoReplaceCopy.cancel)
            .accessibilityHint(PhotoReplaceCopy.staysOnDevice)
            .accessibilityAddTraits(.isButton)
        } message: {
            Text(PhotoReplaceCopy.staysOnDevice)
        }
    }

    private var liveGarment: StubGarment? {
        guard let id = model.selectedGarment?.id else { return model.selectedGarment }
        return model.garments.first(where: { $0.id == id }) ?? model.selectedGarment
    }

    private func hero(_ g: StubGarment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            FixtureImageView(garment: g, presentation: .hero)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel(g.isUserPhoto ? "Photo of \(g.displayName)" : "Fixture image for \(g.displayName)")
                .id(g.imagePath ?? g.id.uuidString)
            Button(PhotoReplaceCopy.changePhoto) {
                photoReplaceSession.attach(model, store: persistenceStore)
                showPhotoReplaceSource = true
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, minHeight: 44)
            .disabled(photoReplaceSession.state.commitInFlight)
            .accessibilityLabel(PhotoReplaceCopy.changePhoto)
            .accessibilityHint(
                PhotoReplaceCopy.changePhotoAccessibilityHint(
                    commitInFlight: photoReplaceSession.state.commitInFlight
                )
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("photo.replace.changePhoto")
            .accessibilityFocused($changePhotoFocused)
        }
    }

    private func titleRow(_ g: StubGarment) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(g.displayName)
                .font(.title2.weight(.semibold))
            Spacer()
            AvailabilityBadge(token: g.availabilityToken)
        }
    }

    private var draftBanner: some View {
        Text("Finish details to use this")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var offlineBanner: some View {
        Text("You’re offline — fill details yourself or retry when back online. Draft save still works locally.")
            .font(.footnote)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }

    private func availabilityControl(_ g: StubGarment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Availability").font(.caption).foregroundStyle(.secondary)
            Menu {
                ForEach(AvailabilityToken.allCases, id: \.self) { token in
                    Button {
                        model.setAvailability(g.id, token.rawValue)
                    } label: {
                        Label(token.accessibilityName, systemImage: token.symbolName)
                    }
                }
            } label: {
                HStack {
                    Label(g.availabilityToken.accessibilityName, systemImage: g.availabilityToken.symbolName)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Change availability, currently \(g.availabilityToken.accessibilityName)")
        }
    }

    private func attributes(_ g: StubGarment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Attributes").font(.headline)
            labeled("Slot", g.slot.displayLabel)
            labeled("Color", g.colorPrimary?.name ?? g.colorPrimary?.family ?? "—")
            labeled("Pattern", humanPattern(g.pattern))
            labeled("Surface", humanSurface(g.surface))
            labeled("Formality", DressingCopy.formality(g.formality))
            labeled("Warmth", DressingCopy.warmth(g.warmth))
        }
    }

    private func setMembership(_ g: StubGarment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Set membership").font(.headline)
            if let set = model.setFor(g) {
                labeled("Set", set.displayName)
                labeled("Keep together", set.keepTogether ? "Yes — use whole or not at all" : "No")
                let partners = model.setPartners(for: g)
                if partners.isEmpty {
                    Text("No other members loaded")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Partners: " + partners.map(\.displayName).joined(separator: ", "))
                        .font(.body)
                }
                if let notes = set.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Solo — not in a set")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// P0-2 / #132 — single wear + CPW block using PRD §7.8 display states.
    private func wearAndCPW(_ g: StubGarment) -> some View {
        let confirmed = model.wearCount(for: g.id)
        let summary = CostPerWearCopy.summary(for: g, confirmedWears: confirmed)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Wear + cost per wear").font(.headline)
            Text(summary.wearLine)
                .font(.body)
            if let last = model.lastWornLine(for: g.id) {
                Text(last)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text(summary.cpwLine)
                .font(.body)
            Button(summary.addPriceTitle) {
                showAddPrice = true
            }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
            .accessibilityLabel(summary.addPriceTitle)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel({
            var parts = [summary.wearLine]
            if let last = model.lastWornLine(for: g.id) {
                parts.append(last)
            }
            parts.append(summary.cpwLine)
            return parts.joined(separator: ". ")
        }())
    }

    private var profileNeedsConfirm: Bool {
        model.styleProfile?.confirmedAt == nil
    }

    @ViewBuilder
    private func primaryCTA(_ g: StubGarment) -> some View {
        if g.readiness == .draft {
            Button("Finish details to use this") {
                finishDetailsPresentation = .finish(garmentId: g.id)
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Finish details to use this")
        } else if profileNeedsConfirm {
            Button("Build an outfit around this") {}
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(true)
                .accessibilityLabel("Build an outfit around this, disabled until profile confirmed")
            Button(WearHistoryCopy.profileUnlockFootnote) {
                onOpenProfile?()
            }
            .font(.footnote)
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .accessibilityLabel(WearHistoryCopy.profileUnlockAccessibility)
            .accessibilityHint(WearHistoryCopy.profileUnlockHint)
        } else if let coverage = model.wardrobeCoverage.coverageLine, !model.wardrobeCoverage.meetsGenerationMinimum {
            Button("Build an outfit around this") {}
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(true)
                .accessibilityLabel("Build an outfit around this, disabled. \(coverage)")
            Text(coverage)
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else if g.availability != "AVAILABLE" {
            Button("Build an outfit around this") {}
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(true)
                .accessibilityLabel("Build an outfit around this, disabled until available")
            Text("Mark available to build an outfit around this.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            Button {
                onBuild()
            } label: {
                Text("Build an outfit around this")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Build an outfit around this")
        }
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.body)
        }
    }

    private func humanPattern(_ raw: String?) -> String {
        guard let raw else { return "—" }
        switch raw {
        case "SOLID": return "Solid"
        case "STRIPE": return "Stripe"
        case "CHECK": return "Check"
        case "PLAID": return "Plaid"
        case "HERRINGBONE": return "Herringbone"
        case "PRINT": return "Print"
        case "TEXTURED_SOLID": return "Textured solid"
        default: return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func handleTakePhotoReplace() {
        guard let id = liveGarment?.id else { return }
        photoReplaceSession.attach(model, store: persistenceStore)
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
                    photoReplaceSession.apply(.chooseSource(.camera, garmentId: id))
                } else {
                    photoReplaceSession.apply(.permissionFallback(granted ? .unavailable : .denied))
                }
            }
        case .presentCamera:
            photoReplaceSession.apply(.chooseSource(.camera, garmentId: id))
        case .offerSettingsOrFallback:
            photoReplaceSession.apply(.permissionFallback(state))
        }
    }

    @MainActor
    private func deleteConfirmedGarment() async {
        guard let id = liveGarment?.id else { return }
        await model.deleteGarment(id: id)
        if model.garments.contains(where: { $0.id == id }) == false {
            dismiss()
        }
    }

    private func humanSurface(_ raw: String?) -> String {
        guard let raw else { return "—" }
        switch raw {
        case "SMOOTH": return "Smooth"
        case "MATTE": return "Matte"
        case "TEXTURED": return "Textured"
        case "NAPPED": return "Napped"
        case "RUGGED": return "Rugged"
        default: return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }


}

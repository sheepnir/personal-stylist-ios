import SwiftUI

/// Bottom Save / Save as draft bar (#279). Same ViewThatFits + 44 pt targets as before.
struct FinishDetailsSaveBar: View {
    var primaryTitle: String
    var canMarkReady: Bool
    var canSaveDraft: Bool
    var isSaving: Bool
    var remainingDraftCount: Int
    var showsNextDraftQueue: Bool
    var saveHint: String = ""
    var saveAsDraftHint: String = ""
    var onSaveReady: () -> Void
    var onSaveDraft: () -> Void
    var onNextDraft: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            ViewThatFits(in: .horizontal) {
                saveButtons(axis: .horizontal)
                saveButtons(axis: .vertical)
            }
            if showsNextDraftQueue, remainingDraftCount > 0 {
                Button("Next draft (\(remainingDraftCount) left)") {
                    onNextDraft()
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityLabel("Next draft, \(remainingDraftCount) left")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .accessibilityIdentifier("finish.details.saveBar")
    }

    private enum BarAxis { case horizontal, vertical }

    @ViewBuilder
    private func saveButtons(axis: BarAxis) -> some View {
        let saveButton = Button(primaryTitle) { onSaveReady() }
            .buttonStyle(.borderedProminent)
            .disabled(!canMarkReady || isSaving)
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity, minHeight: 44)
            .accessibilityLabel(primaryTitle)
            .accessibilityHint(saveHint)
            .accessibilityIdentifier("finish.details.save")
        let draftButton = Button(GarmentEditCopy.saveAsDraft) { onSaveDraft() }
            .buttonStyle(.bordered)
            .disabled(!canSaveDraft || isSaving)
            .frame(maxWidth: .infinity, minHeight: 44)
            .accessibilityLabel(GarmentEditCopy.saveAsDraft)
            .accessibilityHint(saveAsDraftHint)
            .accessibilityIdentifier("finish.details.saveAsDraft")
        switch axis {
        case .horizontal:
            HStack(spacing: 12) { saveButton; draftButton }
        case .vertical:
            VStack(spacing: 8) { saveButton; draftButton }
        }
    }
}

/// Selected unknown/custom colour row — visible, named, and marked selected (#279).
struct FinishDetailsCustomColorRow: View {
    let state: FinishDetailsColorState

    var body: some View {
        let hex = state.hex
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: hex) ?? .gray)
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(checkForeground(hex: hex))
            }
            .frame(width: 52, height: 36)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary, lineWidth: 2)
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(state.accessibilityLabel)
                    .font(.subheadline)
                Text("Current colour")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(state.accessibilityLabel)
        .accessibilityValue(GarmentEditCopy.selectedValue)
        .accessibilityAddTraits(.isSelected)
        .accessibilityIdentifier("finish.details.color.custom")
    }

    private func checkForeground(hex: String) -> Color {
        let folded = hex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if folded == "#f5f5f0" || folded == "#e8dcc8" || folded == "#d4b84a" {
            return .black
        }
        return .white
    }
}

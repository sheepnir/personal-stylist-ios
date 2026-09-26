import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension LoopDemoModel {
    /// Post a short confirmation toast with VoiceOver announcement (#105).
    func showToast(_ message: String, dismissAfter: Duration = .seconds(2.5), announce: Bool = true) {
        toastDismissTask?.cancel()
        swapUndoAssignmentsSnapshot = nil
        updateToastState(message)
        if announce {
            AccessibilityNotification.Announcement(message).post()
        }
        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(for: dismissAfter)
            guard !Task.isCancelled else { return }
            clearActiveToast()
        }
    }

    /// Swap apply feedback — longer window for Undo (#109 / #105).
    func showSwapAppliedToast(_ message: String, undoSnapshot: [StubOutfitAssignment]) {
        toastDismissTask?.cancel()
        swapUndoAssignmentsSnapshot = undoSnapshot
        updateToastState(message, undoAvailable: true)
        AccessibilityNotification.Announcement(message).post()
        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            clearActiveToast()
        }
    }

    func performSwapUndo() {
        guard var current = outfit, let snapshot = swapUndoAssignmentsSnapshot else { return }
        current.assignments = snapshot
        outfit = current
        clearActiveToast()
        let message = "Swap undone"
        updateToastState(message)
        AccessibilityNotification.Announcement(message).post()
        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            clearActiveToast()
        }
        recordDiagnostic("Swap undone")
    }

    func clearActiveToast() {
        toastDismissTask?.cancel()
        updateToastState(nil)
        swapUndoAssignmentsSnapshot = nil
    }

    /// Auto-dismiss “Updated” flash on the board (#105 / soft #137).
    func scheduleBoardUpdatedFlashDismiss() {
        boardFlashDismissTask?.cancel()
        boardFlashDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            boardUpdatedFlash = false
        }
    }

    func bumpLightHaptic() {
#if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
#endif
    }

    /// #127 — success moment on Wearing this (haptic + VoiceOver; matches on-screen title).
    func notifyWearLoggedForToday() {
#if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
#endif
        AccessibilityNotification.Announcement("Logged for today.").post()
    }

}

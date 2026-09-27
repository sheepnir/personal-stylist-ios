import Foundation

/// #45 / #46 — board-only fallback notice (spec R9, §2.5). The notice belongs to the
/// displayed outfit's stored generation record, so it follows the outfit: kept on swap,
/// Keep / Unlock and offline reuse; replaced by a new result; restored with a prior outfit.
extension LoopDemoModel {
    /// Notice for the board, or `nil`. Hidden while a generate is in flight (skeleton).
    var boardFallbackNotice: FallbackNotice? {
        guard !isGenerating,
              let outfit,
              !outfit.assignments.contains(where: \.isSkeletonPlaceholder) else { return nil }
        return FallbackNoticeCopy.notice(for: outfit.generation)
    }

    /// Announce once when a newly generated outfit lands with a notice. Restores
    /// (cancel, failure, no alternative) and re-display never call this.
    func announceFallbackNoticeIfPresent(for newOutfit: StubOutfit) {
        guard let notice = FallbackNoticeCopy.notice(for: newOutfit.generation) else { return }
        postAccessibilityAnnouncement(notice.accessibilityLabel)
    }
}

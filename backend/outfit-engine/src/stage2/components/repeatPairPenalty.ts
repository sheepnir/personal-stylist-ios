import type {
  GarmentSummary,
  ScoringConfig,
  Stage2History,
} from "../../types.js";
import { daysBetween } from "../../utils/dates.js";

/**
 * If (g, fixedPiece) co-appear in suggested outfits within windowDays → penalty.
 * Absent history → 0 (M0-15 stub).
 * Invalid dates: suggestions with unparseable dates are skipped.
 */
export function repeatPairPenalty(
  g: GarmentSummary,
  fixedPieces: GarmentSummary[],
  asOfDate: string,
  history: Stage2History | null | undefined,
  config: ScoringConfig,
): number {
  if (!history?.suggestions || history.suggestions.length === 0) return 0;
  if (fixedPieces.length === 0) return 0;

  const window = config.repeatPair.windowDays;
  const fixedIds = new Set(fixedPieces.map((p) => p.id));
  let hits = 0;
  let considered = 0;

  for (const s of history.suggestions) {
    const age = daysBetween(asOfDate, s.suggestedAt);
    // Skip suggestions with invalid dates
    if (age === null || age > window) continue;
    considered += 1;
    const ids = new Set(s.garmentIds);
    if (!ids.has(g.id)) continue;
    for (const fid of fixedIds) {
      if (ids.has(fid)) {
        hits += 1;
        break;
      }
    }
  }

  if (considered === 0 || hits === 0) return 0;
  return Math.min(1, hits / Math.max(considered, 1));
}

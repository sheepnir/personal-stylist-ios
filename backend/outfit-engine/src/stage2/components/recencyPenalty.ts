import type {
  GarmentSummary,
  ScoringConfig,
  Stage2History,
} from "../../types.js";
import { daysBetween } from "../../utils/dates.js";

/**
 * If worn within windowDays: (windowDays − daysSinceWear) / windowDays, else 0.
 * Absent history and no lastWornOn → 0 (M0-15 stub).
 * Invalid dates: treated as null (no penalty).
 */
export function recencyPenalty(
  g: GarmentSummary,
  asOfDate: string,
  history: Stage2History | null | undefined,
  config: ScoringConfig,
): number {
  const window = config.recency.windowDays;
  let daysSince: number | null = null;

  if (history?.wears && history.wears.length > 0) {
    let mostRecent: string | null = null;
    for (const w of history.wears) {
      if (w.garmentId !== g.id) continue;
      if (mostRecent == null || w.wornOn > mostRecent) mostRecent = w.wornOn;
    }
    if (mostRecent) {
      daysSince = daysBetween(asOfDate, mostRecent);
    }
  }
  
  // If history didn't provide a valid date, try lastWornOn
  if (daysSince == null && g.lastWornOn) {
    daysSince = daysBetween(asOfDate, g.lastWornOn);
  }

  // If date parsing failed (null) or item not worn recently, no penalty
  if (daysSince == null || daysSince >= window) return 0;
  return (window - daysSince) / window;
}

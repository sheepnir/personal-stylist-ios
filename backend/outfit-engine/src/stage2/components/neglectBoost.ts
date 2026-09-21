import type { GarmentSummary, ScoringConfig } from "../../types.js";
import { daysBetween } from "../../utils/dates.js";

/**
 * min(daysSinceLastWear / horizonDays, 1) × wantToWearMoreMultiplier, capped at 1.
 * Never-worn: daysSinceIntake, or 0.5 if both null.
 * Invalid dates: treated as null (fallback to 0.5).
 */
export function neglectBoost(
  g: GarmentSummary,
  asOfDate: string,
  config: ScoringConfig,
): number {
  const horizon = config.neglect.horizonDays;
  let days: number | null = null;

  if (g.lastWornOn) {
    days = daysBetween(asOfDate, g.lastWornOn);
  }
  
  // If daysBetween returned null (invalid date), fall through to daysSinceIntake
  if (days == null && g.daysSinceIntake != null) {
    days = g.daysSinceIntake;
  }

  let raw: number;
  if (days == null) {
    raw = 0.5;
  } else {
    raw = Math.min(days / horizon, 1);
  }

  if (g.wantToWearMore) {
    raw *= config.neglect.wantToWearMoreMultiplier;
  }
  return Math.min(raw, 1);
}

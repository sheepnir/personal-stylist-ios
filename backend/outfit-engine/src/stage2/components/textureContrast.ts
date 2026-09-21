import type { GarmentSummary } from "../../types.js";

/**
 * Reward surface ≠ majority of O; penalise adding a third identical surface.
 * Missing surface → 0.5.
 */
export function textureContrast(
  g: GarmentSummary,
  fixedPieces: GarmentSummary[],
): number {
  const surface = g.surface?.toUpperCase() ?? null;
  if (surface == null) return 0.5;
  if (fixedPieces.length === 0) return 0.75;

  const counts = new Map<string, number>();
  for (const o of fixedPieces) {
    const s = o.surface?.toUpperCase();
    if (!s) continue;
    counts.set(s, (counts.get(s) ?? 0) + 1);
  }
  if (counts.size === 0) return 0.75;

  let majority = "";
  let majorityCount = 0;
  for (const [s, c] of counts) {
    if (c > majorityCount) {
      majority = s;
      majorityCount = c;
    }
  }

  const sameCount = counts.get(surface) ?? 0;
  // Adding a third identical surface → heavy penalty
  if (sameCount >= 2) return 0.15;
  // Matches majority → low contrast
  if (surface === majority) return 0.35;
  // Differs from majority → good contrast
  return 0.95;
}

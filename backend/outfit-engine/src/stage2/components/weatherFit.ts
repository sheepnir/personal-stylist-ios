import { WARMTH_TOLERANCE } from "../../types.js";
import type { ContextSnapshot, GarmentSummary } from "../../types.js";

/**
 * Where g.warmth sits inside the Stage 1 *base* band for temperatureBand.
 * Centre of band → 1; edges → lower; missing warmth → 0.5.
 */
export function weatherFit(
  g: GarmentSummary,
  context: ContextSnapshot,
): number {
  if (g.warmth == null) return 0.5;
  const [lo, hi] = WARMTH_TOLERANCE[context.temperatureBand];
  if (g.warmth < lo || g.warmth > hi) {
    // Outside base band (may have entered via Stage 1 widen) → low
    const dist = g.warmth < lo ? lo - g.warmth : g.warmth - hi;
    return Math.max(0.1, 0.4 / (1 + dist));
  }
  const mid = (lo + hi) / 2;
  const half = Math.max((hi - lo) / 2, 0.5);
  const dist = Math.abs(g.warmth - mid);
  return 1 - (dist / half) * 0.35;
}

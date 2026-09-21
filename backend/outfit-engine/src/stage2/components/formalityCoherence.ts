import type {
  ContextSnapshot,
  GarmentSummary,
  ScoringConfig,
} from "../../types.js";

/**
 * Spread of {g.formality} ∪ formality(O) ∪ {ctx.occasionFormality}.
 * Spread ≤ 2 → high; spread > maxSpreadBeforeNearZero → near 0.
 */
export function formalityCoherence(
  g: GarmentSummary,
  fixedPieces: GarmentSummary[],
  context: ContextSnapshot,
  config: ScoringConfig,
): number {
  if (g.formality == null) return 0.5;
  const values: number[] = [g.formality, context.occasionFormality];
  for (const o of fixedPieces) {
    if (o.formality != null) values.push(o.formality);
  }
  const spread = Math.max(...values) - Math.min(...values);
  const max = config.formality.maxSpreadBeforeNearZero;
  if (spread <= max) {
    // 0 spread → 1; at max → ~0.7
    return 1 - (spread / Math.max(max, 1)) * 0.3;
  }
  // Beyond max → near zero, decaying further
  const over = spread - max;
  return Math.max(0.05, 0.2 / (1 + over));
}

import type { GarmentSummary, ScoringConfig } from "../../types.js";

function familyOf(g: GarmentSummary): string | null {
  const f = g.colorPrimary?.family;
  return f && f.length > 0 ? f.toLowerCase() : null;
}

function isNeutral(family: string, config: ScoringConfig): boolean {
  return config.color.neutrals.map((n) => n.toLowerCase()).includes(family);
}

function sameAnalogousGroup(
  a: string,
  b: string,
  config: ScoringConfig,
): boolean {
  for (const group of config.color.analogousGroups ?? []) {
    const set = new Set(group.map((x) => x.toLowerCase()));
    if (set.has(a) && set.has(b)) return true;
  }
  return false;
}

function isComplementary(
  a: string,
  b: string,
  config: ScoringConfig,
): boolean {
  for (const [x, y] of config.color.complementaryPairs ?? []) {
    const xl = x.toLowerCase();
    const yl = y.toLowerCase();
    if ((a === xl && b === yl) || (a === yl && b === xl)) return true;
  }
  return false;
}

/** Pairwise harmony 0..1 between two colour families. */
export function pairHarmony(
  aFamily: string | null,
  bFamily: string | null,
  config: ScoringConfig,
): number {
  if (aFamily == null || bFamily == null) return 0.5;
  if (aFamily === bFamily) return 0.9;
  if (isNeutral(aFamily, config) || isNeutral(bFamily, config)) return 1.0;
  if (sameAnalogousGroup(aFamily, bFamily, config)) return 0.85;
  if (isComplementary(aFamily, bFamily, config)) return 0.8;
  // Two saturated non-neutrals that clash
  return 0.25;
}

/**
 * Average pairwise harmony of g vs each fixed piece.
 * Empty O → 0.75 (no clash possible). Missing colour → mid 0.5.
 */
export function colorHarmony(
  g: GarmentSummary,
  fixedPieces: GarmentSummary[],
  config: ScoringConfig,
): number {
  const gf = familyOf(g);
  if (gf == null) return 0.5;
  if (fixedPieces.length === 0) return 0.75;
  let sum = 0;
  for (const o of fixedPieces) {
    sum += pairHarmony(gf, familyOf(o), config);
  }
  return sum / fixedPieces.length;
}

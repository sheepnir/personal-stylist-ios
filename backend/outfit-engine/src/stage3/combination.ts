import type {
  GarmentSummary,
  PreferenceRule,
  Slot,
} from "../types.js";
import {
  ruleInScope,
  isComboNegative,
  garmentPair,
  colorFamilyPair,
} from "../shared/combinationRules.js";

export function activeCombinationRules(
  rules: PreferenceRule[] | undefined,
  occasion: string,
): PreferenceRule[] {
  return (rules ?? []).filter(
    (r) => isComboNegative(r) && ruleInScope(r, occasion),
  );
}

/**
 * True iff placing `garment` into current outfit O would complete a forbidden
 * DISLIKE/AVOID_HARD combination (garment pair or colour-family pair).
 * Does not strip pieces already in O (locked disliked pair stays).
 */
export function completesForbiddenPair(
  garment: GarmentSummary,
  outfitIds: Set<string>,
  outfitGarments: GarmentSummary[],
  rules: PreferenceRule[],
): boolean {
  for (const rule of rules) {
    const gp = garmentPair(rule.subject);
    if (gp) {
      const [a, b] = gp;
      const partner = garment.id === a ? b : garment.id === b ? a : null;
      if (partner != null && outfitIds.has(partner)) return true;
      continue;
    }
    const cp = colorFamilyPair(rule.subject);
    if (cp) {
      const [fa, fb] = cp;
      const gf = garment.colorPrimary?.family?.toLowerCase();
      if (!gf) continue;
      for (const other of outfitGarments) {
        const ff = other.colorPrimary?.family?.toLowerCase();
        if (!ff) continue;
        if ((gf === fa && ff === fb) || (gf === fb && ff === fa)) return true;
      }
    }
  }
  return false;
}

/** Both sides of a negative combo already present in outfit (caution). */
export function lockedDislikedPairsPresent(
  outfitIds: Set<string>,
  rules: PreferenceRule[],
): PreferenceRule[] {
  const hits: PreferenceRule[] = [];
  for (const rule of rules) {
    const gp = garmentPair(rule.subject);
    if (!gp) continue;
    const [a, b] = gp;
    if (outfitIds.has(a) && outfitIds.has(b)) hits.push(rule);
  }
  return hits;
}

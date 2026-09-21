import type {
  CombinationExclusion,
  ContextSnapshot,
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

export interface ComboResult {
  eligibleAfterCombo: Partial<Record<Slot, GarmentSummary[]>>;
  excludedByCombination: CombinationExclusion[];
}

/**
 * D-26: exclude candidates that complete a forbidden pair with a fixed piece.
 * Both members fixed → no exclusion (user explicit choice).
 */
export function applyCombinationExclusion(
  eligible: Partial<Record<Slot, GarmentSummary[]>>,
  fixedPieces: GarmentSummary[],
  fixedIds: Set<string>,
  fixedSlots: Set<Slot>,
  rules: PreferenceRule[],
  context: ContextSnapshot,
): ComboResult {
  const active = rules.filter(
    (r) => isComboNegative(r) && ruleInScope(r, context.occasion),
  );
  const excludedByCombination: CombinationExclusion[] = [];
  const eligibleAfterCombo: Partial<Record<Slot, GarmentSummary[]>> = {};

  for (const [slot, garments] of Object.entries(eligible) as [
    Slot,
    GarmentSummary[],
  ][]) {
    if (fixedSlots.has(slot) && slot !== "ACCESSORY") {
      // Occupied slots are not ranked; leave empty for shortlist loop
      eligibleAfterCombo[slot] = [];
      continue;
    }

    const kept: GarmentSummary[] = [];
    for (const g of garments) {
      if (fixedIds.has(g.id)) continue; // fixed never shortlisted for own slot

      let excluded = false;
      for (const rule of active) {
        const gp = garmentPair(rule.subject);
        if (gp) {
          const [a, b] = gp;
          const partner =
            g.id === a ? b : g.id === b ? a : null;
          if (partner == null) continue;
          // Both fixed → keep
          if (fixedIds.has(g.id) && fixedIds.has(partner)) continue;
          if (fixedIds.has(partner)) {
            excludedByCombination.push({
              garmentId: g.id,
              slot,
              ruleId: rule.id ?? null,
              againstFixedId: partner,
              reason: "COMBINATION_WITH_FIXED",
            });
            excluded = true;
            break;
          }
          continue;
        }

        const cp = colorFamilyPair(rule.subject);
        if (cp) {
          const [fa, fb] = cp;
          const gf = g.colorPrimary?.family?.toLowerCase();
          if (!gf) continue;
          for (const fixed of fixedPieces) {
            const ff = fixed.colorPrimary?.family?.toLowerCase();
            if (!ff) continue;
            const match =
              (gf === fa && ff === fb) || (gf === fb && ff === fa);
            if (match) {
              excludedByCombination.push({
                garmentId: g.id,
                slot,
                ruleId: rule.id ?? null,
                againstFixedId: fixed.id,
                reason: "COMBINATION_WITH_FIXED",
              });
              excluded = true;
              break;
            }
          }
          if (excluded) break;
        }
      }
      if (!excluded) kept.push(g);
    }
    eligibleAfterCombo[slot] = kept;
  }

  return { eligibleAfterCombo, excludedByCombination };
}

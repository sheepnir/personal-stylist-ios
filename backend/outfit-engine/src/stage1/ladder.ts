import {
  TIER0,
  TIER_FORMALITY,
  TIER_WARMTH,
  type FilterTier,
} from "./filters.js";
import type { Relaxation, Slot } from "../types.js";

export type LadderTier = 0 | 1 | 2 | 3;

/** Map ladder tier → filter tier. Tier 3 = abandoned (no refilter). */
export function filterTierForLadder(tier: LadderTier): FilterTier | null {
  switch (tier) {
    case 0:
      return TIER0;
    case 1:
      return TIER_FORMALITY;
    case 2:
      return TIER_WARMTH;
    case 3:
      return null;
  }
}

export function relaxationForStep(
  tier: 1 | 2 | 3,
  slot: Slot,
): Relaxation {
  if (tier === 1) {
    return {
      step: "FORMALITY_WIDENED",
      slot,
      note: "Formality window widened to ±2",
    };
  }
  if (tier === 2) {
    return {
      step: "WARMTH_WIDENED",
      slot,
      note: "Warmth tolerance widened by one step",
    };
  }
  return {
    step: "SLOT_ABANDONED",
    slot,
    note: "No eligible garments after formality and warmth widening",
  };
}

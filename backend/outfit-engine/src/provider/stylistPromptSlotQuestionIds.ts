import type { Slot } from "../types.js";

/**
 * Slot choice question ids mirrored from A-2 `decisionsQuestionIds.ts`
 * (`slot_<SLOT>`). Keep in sync with that file; do not import across branches.
 * Accessory noul question ids are defined by the A-3 request builder only.
 */
export const SLOT_CHOICE_QUESTION_SLOTS: readonly Slot[] = [
  "TOP",
  "MID_LAYER",
  "JACKET",
  "OUTERWEAR",
  "BOTTOM",
  "FOOTWEAR",
] as const;

export function slotChoiceQuestionId(slot: Slot): string {
  return `slot_${slot}`;
}

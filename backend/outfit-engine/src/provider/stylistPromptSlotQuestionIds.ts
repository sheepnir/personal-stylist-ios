import type { Slot } from "../types.js";

/**
 * Canonical `slot_<SLOT>` question-id contract (ADR-0001 §7.1.2).
 * A-1 owns this barrel export; the stage-4 provider validator must import
 * `slotChoiceQuestionId` and `SLOT_CHOICE_QUESTION_SLOTS` from here and must
 * never re-define them. Accessory noul question ids are defined by the A-3
 * request builder only.
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

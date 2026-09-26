import type { Slot } from "../types.js";
import { ownHas } from "./safeOwn.js";
import type { ProviderQuestion } from "./types.js";

/**
 * Choice question ids for fillable slots (ADR-0001 §7.1.2).
 * Slot segment values match `SLOT_ENUM` in A-1 `outfit-t2-v1-answerTypes.ts`.
 */
export function slotChoiceQuestionId(slot: Slot): string {
  return `slot_${slot}`;
}

export function parseSlotChoiceQuestionId(id: string): Slot | null {
  if (!id.startsWith("slot_")) return null;
  const slot = id.slice("slot_".length) as Slot;
  return slot.length > 0 ? slot : null;
}

/** Reject malformed question ids before parsing provider answers. */
export function providerQuestionsMatchSlotIdContract(
  questions: ProviderQuestion[],
  requiredSlots?: Set<Slot>,
): boolean {
  const seen = new Set<string>();
  for (const q of questions) {
    if (seen.has(q.id)) return false;
    seen.add(q.id);
    if (q.type === "choice") {
      if (q.id !== slotChoiceQuestionId(q.slot)) return false;
      if (
        requiredSlots?.has(q.slot) &&
        ownHas(q.options, "none")
      ) {
        return false;
      }
    }
  }
  return true;
}

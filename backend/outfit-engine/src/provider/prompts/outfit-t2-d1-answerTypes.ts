import type { JSONSchema7 } from "../jsonSchemaTypes.js";
import { deepFreeze } from "../promptImmutability.js";
import {
  slotChoiceQuestionId,
  SLOT_CHOICE_QUESTION_SLOTS,
} from "../stylistPromptSlotQuestionIds.js";

const CHOICE_ANSWER_TYPE: JSONSchema7 = {
  type: "object",
  additionalProperties: false,
  required: ["type", "choice"],
  properties: {
    type: { const: "choice" },
    choice: {
      type: "string",
      description: "One supplied option key from the question's choice list.",
    },
    confidence: { type: "number" },
    probabilities: {
      type: "object",
      additionalProperties: { type: "number" },
    },
  },
};

/** Per-slot typed Decisions answers keyed by `slot_<SLOT>` (ADR-0001 §7.1, §8). No free text. */
export const OUTFIT_T2_D1_ANSWER_TYPES: Readonly<Record<string, JSONSchema7>> =
  deepFreeze(
    Object.fromEntries(
      SLOT_CHOICE_QUESTION_SLOTS.map((slot) => [
        slotChoiceQuestionId(slot),
        structuredClone(CHOICE_ANSWER_TYPE),
      ]),
    ),
  );

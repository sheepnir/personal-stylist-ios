import type { JSONSchema7 } from "../jsonSchemaTypes.js";
import { deepFreeze } from "../promptImmutability.js";

const SLOT_ENUM = [
  "TOP",
  "MID_LAYER",
  "JACKET",
  "OUTERWEAR",
  "BOTTOM",
  "FOOTWEAR",
  "ACCESSORY",
] as const;

/** Structured answer types for outfit-t2-v1 (ADR-0001 §6 step 1). Part of the prompt version. */
export const OUTFIT_T2_V1_ANSWER_TYPES: JSONSchema7 = deepFreeze({
  type: "object",
  additionalProperties: false,
  required: ["assignments", "rationale"],
  properties: {
    assignments: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["slot", "garment"],
        properties: {
          slot: {
            type: "string",
            enum: [...SLOT_ENUM],
          },
          garment: { type: ["string", "null"] },
          gapReason: { type: "string", maxLength: 120 },
        },
      },
    },
    rationale: {
      type: "object",
      additionalProperties: false,
      required: ["summary"],
      properties: {
        summary: { type: "string", maxLength: 200 },
        pairingNotes: {
          type: "array",
          items: { type: "string", maxLength: 140 },
          maxItems: 3,
        },
        teachingNote: { type: ["string", "null"], maxLength: 160 },
        cautions: {
          type: "array",
          items: { type: "string", maxLength: 120 },
          maxItems: 2,
        },
      },
    },
  },
});

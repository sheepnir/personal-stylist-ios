import type { JSONSchema7 } from "../jsonSchemaTypes.js";
import type { StylistPromptModule, StylistProviderPayload } from "../types.js";

const SLOT_ENUM = [
  "TOP",
  "MID_LAYER",
  "JACKET",
  "OUTERWEAR",
  "BOTTOM",
  "FOOTWEAR",
  "ACCESSORY",
] as const;

/** Model output schema for outfit-t2-v1 (ADR-0001 §6 step 1). Part of the prompt version. */
export const OUTFIT_T2_V1_OUTPUT_SCHEMA: JSONSchema7 = {
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
};

const SYSTEM = `You are a personal stylist selecting garments from a fixed shortlist only.

Rules:
- Assign at most one garment per non-accessory slot; up to three ACCESSORY rows.
- Reference garments in rationale text only as placeholders like {g_4f2a}, matching assigned tokens.
- Respect isAnchor and isLocked constraints in the payload.
- If a required slot cannot be filled, set garment to null and provide gapReason (≤120 chars).
- Output JSON only, matching the required schema exactly. No extra properties.`;

function render(payload: StylistProviderPayload): string {
  return JSON.stringify(payload);
}

export const outfitT2V1: StylistPromptModule = {
  version: "outfit-t2-v1",
  system: SYSTEM,
  render,
  outputSchema: OUTFIT_T2_V1_OUTPUT_SCHEMA,
};

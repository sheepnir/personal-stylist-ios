import type { StylistPromptModule } from "../promptVersionTypes.js";
import { OUTFIT_T2_V1_ANSWER_TYPES } from "./outfit-t2-v1-answerTypes.js";
import { OUTFIT_T2_V1_OPTION_DESCRIPTIONS } from "./outfit-t2-v1-optionDescriptions.js";

const INSTRUCTION_TEXT = `You are a personal stylist selecting garments from a fixed shortlist only.

Rules:
- Assign at most one garment per non-accessory slot; up to three ACCESSORY rows.
- Reference garments in rationale text only as placeholders like {g_4f2a}, matching assigned tokens.
- Respect isAnchor and isLocked constraints in the decision input.
- If a required slot cannot be filled, set garment to null and provide gapReason (≤120 chars).
- Respond using the configured answer types exactly. No extra properties.`;

export const outfitT2V1: StylistPromptModule = {
  version: "outfit-t2-v1",
  instructionText: INSTRUCTION_TEXT,
  optionDescriptions: OUTFIT_T2_V1_OPTION_DESCRIPTIONS,
  answerTypes: OUTFIT_T2_V1_ANSWER_TYPES,
};

export { OUTFIT_T2_V1_ANSWER_TYPES } from "./outfit-t2-v1-answerTypes.js";
export { OUTFIT_T2_V1_OPTION_DESCRIPTIONS } from "./outfit-t2-v1-optionDescriptions.js";

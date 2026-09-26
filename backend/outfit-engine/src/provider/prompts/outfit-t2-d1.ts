import { deepFreeze } from "../promptImmutability.js";
import type { StylistPromptModule } from "../promptVersionTypes.js";
import { OUTFIT_T2_D1_ANSWER_TYPES } from "./outfit-t2-d1-answerTypes.js";
import { OUTFIT_T2_D1_OPTION_DESCRIPTIONS } from "./outfit-t2-d1-optionDescriptions.js";

const INSTRUCTION_TEXT = `Select outfit slots using typed Decisions answers only.

For each slot question id (slot_<SLOT>), respond with a choice answer whose value is one of the option keys listed for that question.
Do not emit any fields outside the configured answer types.
Accessory questions, when present, use ids assigned by the request builder (not defined in this prompt version).`;

export const outfitT2D1: StylistPromptModule = deepFreeze({
  version: "outfit-t2-d1",
  instructionText: INSTRUCTION_TEXT,
  optionDescriptions: OUTFIT_T2_D1_OPTION_DESCRIPTIONS,
  answerTypes: OUTFIT_T2_D1_ANSWER_TYPES,
});

export { OUTFIT_T2_D1_ANSWER_TYPES } from "./outfit-t2-d1-answerTypes.js";
export { OUTFIT_T2_D1_OPTION_DESCRIPTIONS } from "./outfit-t2-d1-optionDescriptions.js";

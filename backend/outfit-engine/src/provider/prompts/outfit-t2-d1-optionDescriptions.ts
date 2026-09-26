import type { StylistPromptOptionDescription } from "../promptVersionTypes.js";
import { deepFreeze } from "../promptImmutability.js";
import {
  slotChoiceQuestionId,
  SLOT_CHOICE_QUESTION_SLOTS,
} from "../stylistPromptSlotQuestionIds.js";

/** Describes typed slot choice questions only (accessory ids come from A-3). */
export const OUTFIT_T2_D1_OPTION_DESCRIPTIONS: readonly StylistPromptOptionDescription[] =
  deepFreeze(
    SLOT_CHOICE_QUESTION_SLOTS.map((slot) => ({
      questionId: slotChoiceQuestionId(slot),
      description:
        `For ${slot}, pick exactly one option key from the supplied choice list using a typed choice answer.`,
    })),
  );

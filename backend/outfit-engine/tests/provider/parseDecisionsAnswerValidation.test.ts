import { describe, expect, it } from "vitest";
import { createOwnRecord } from "../../src/provider/safeOwn.js";
import { slotChoiceQuestionId } from "../../src/provider/decisionsQuestionIds.js";
import {
  validateDecisionsAnswersAgainstQuestions,
  validateProviderChoiceAnswers,
} from "../../src/provider/parseDecisionsOutput.js";
import type { ProviderQuestion } from "../../src/provider/types.js";

const SUIT_JACKET = "a1000003-0003-4000-8000-000000000003";
const SUIT_TROUSERS = "a1000005-0005-4000-8000-000000000004";

describe("validateDecisionsAnswersAgainstQuestions", () => {
  it("requires exact question id coverage", () => {
    const topId = slotChoiceQuestionId("TOP");
    const opts = createOwnRecord<unknown>();
    opts.g_1 = {};
    const questions: ProviderQuestion[] = [
      {
        id: topId,
        type: "choice",
        slot: "TOP",
        options: opts,
      },
    ];
    expect(
      validateDecisionsAnswersAgainstQuestions(
        { [topId]: { type: "choice", choice: "g_1" }, extra: { type: "choice", choice: "g_1" } },
        questions,
      ),
    ).toBe(false);
  });
});

describe("validateProviderChoiceAnswers", () => {
  it("rejects set token when firstSlot does not match question slot", () => {
    const setToken = "s_suit";
    const topId = slotChoiceQuestionId("TOP");
    const bottomId = slotChoiceQuestionId("BOTTOM");
    const questions: ProviderQuestion[] = [
      { id: topId, type: "choice", slot: "TOP", options: { [setToken]: {} } },
      { id: bottomId, type: "choice", slot: "BOTTOM", options: { none: {} } },
    ];
    const answers = {
      [topId]: { type: "choice" as const, choice: setToken },
      [bottomId]: { type: "choice" as const, choice: "none" },
    };
    expect(
      validateProviderChoiceAnswers({
        answers,
        questions,
        requiredSlots: new Set(),
        setTokens: [
          {
            token: setToken,
            firstSlot: "JACKET",
            memberGarmentIds: [SUIT_JACKET, SUIT_TROUSERS],
            memberSlots: ["JACKET", "BOTTOM"],
          },
        ],
      }),
    ).toBe(false);
  });

  it("rejects empty set members", () => {
    const setToken = "s_empty";
    const jacketId = slotChoiceQuestionId("JACKET");
    const questions: ProviderQuestion[] = [
      { id: jacketId, type: "choice", slot: "JACKET", options: { [setToken]: {} } },
    ];
    expect(
      validateProviderChoiceAnswers({
        answers: {
          [jacketId]: { type: "choice" as const, choice: setToken },
        },
        questions,
        requiredSlots: new Set(),
        setTokens: [
          {
            token: setToken,
            firstSlot: "JACKET",
            memberGarmentIds: [],
            memberSlots: [],
          },
        ],
      }),
    ).toBe(false);
  });

  it("rejects none on a required slot", () => {
    const bottomId = slotChoiceQuestionId("BOTTOM");
    const questions: ProviderQuestion[] = [
      {
        id: bottomId,
        type: "choice",
        slot: "BOTTOM",
        options: { none: {}, g_bot: {} },
      },
    ];
    expect(
      validateProviderChoiceAnswers({
        answers: {
          [bottomId]: { type: "choice" as const, choice: "none" },
        },
        questions,
        requiredSlots: new Set(["BOTTOM"]),
      }),
    ).toBe(false);
  });
});

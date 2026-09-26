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

function choiceQuestion(
  slot: "TOP" | "BOTTOM" | "JACKET",
  options: Record<string, unknown>,
): ProviderQuestion {
  return {
    id: slotChoiceQuestionId(slot),
    type: "choice",
    slot,
    options,
  };
}

describe("validateDecisionsAnswersAgainstQuestions", () => {
  const topId = slotChoiceQuestionId("TOP");
  const topOpts = createOwnRecord<unknown>();
  topOpts.g_1 = {};

  it("accepts a valid garment choice and noul boundary values", () => {
    const noulId = "acc_q1";
    const questions: ProviderQuestion[] = [
      choiceQuestion("TOP", topOpts),
      { id: noulId, type: "noul", garmentToken: "g_acc" },
    ];
    expect(
      validateDecisionsAnswersAgainstQuestions(
        {
          [topId]: { type: "choice", choice: "g_1" },
          [noulId]: { type: "noul", noul: 0 },
        },
        questions,
      ),
    ).toBe(true);
    expect(
      validateDecisionsAnswersAgainstQuestions(
        {
          [topId]: { type: "choice", choice: "g_1" },
          [noulId]: { type: "noul", noul: 1 },
        },
        questions,
      ),
    ).toBe(true);
  });

  it("requires exact question id coverage", () => {
    const questions: ProviderQuestion[] = [choiceQuestion("TOP", topOpts)];
    expect(
      validateDecisionsAnswersAgainstQuestions(
        {
          [topId]: { type: "choice", choice: "g_1" },
          extra: { type: "choice", choice: "g_1" },
        },
        questions,
      ),
    ).toBe(false);
  });

  it("rejects unknown choice, type mismatch, and missing answers", () => {
    const questions: ProviderQuestion[] = [choiceQuestion("TOP", topOpts)];
    expect(
      validateDecisionsAnswersAgainstQuestions(
        { [topId]: { type: "choice", choice: "g_unknown" } },
        questions,
      ),
    ).toBe(false);
    expect(
      validateDecisionsAnswersAgainstQuestions(
        { [topId]: { type: "noul", noul: 0.5 } },
        questions,
      ),
    ).toBe(false);
    expect(validateDecisionsAnswersAgainstQuestions({}, questions)).toBe(false);
  });

  it("rejects out-of-range noul values", () => {
    const noulId = "acc_q1";
    const questions: ProviderQuestion[] = [
      { id: noulId, type: "noul", garmentToken: "g_acc" },
    ];
    expect(
      validateDecisionsAnswersAgainstQuestions(
        { [noulId]: { type: "noul", noul: -0.01 } },
        questions,
      ),
    ).toBe(false);
    expect(
      validateDecisionsAnswersAgainstQuestions(
        { [noulId]: { type: "noul", noul: 1.01 } },
        questions,
      ),
    ).toBe(false);
  });
});

describe("validateProviderChoiceAnswers", () => {
  it("accepts optional none and a valid set token", () => {
    const setToken = "s_suit";
    const jacketId = slotChoiceQuestionId("JACKET");
    const bottomId = slotChoiceQuestionId("BOTTOM");
    const questions: ProviderQuestion[] = [
      {
        id: jacketId,
        type: "choice",
        slot: "JACKET",
        options: { [setToken]: {} },
      },
      {
        id: bottomId,
        type: "choice",
        slot: "BOTTOM",
        options: { none: {} },
      },
    ];
    const answers = {
      [jacketId]: { type: "choice" as const, choice: setToken },
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
    ).toBe(true);
  });

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

  it("rejects empty set members and unknown set references", () => {
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

    expect(
      validateProviderChoiceAnswers({
        answers: {
          [jacketId]: { type: "choice" as const, choice: "s_missing" },
        },
        questions: [
          {
            id: jacketId,
            type: "choice",
            slot: "JACKET",
            options: { s_missing: {} },
          },
        ],
        requiredSlots: new Set(),
        setTokens: [],
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

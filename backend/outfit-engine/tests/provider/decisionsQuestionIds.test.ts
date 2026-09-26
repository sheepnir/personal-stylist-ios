import { describe, expect, it } from "vitest";
import {
  parseSlotChoiceQuestionId,
  providerQuestionsMatchSlotIdContract,
  slotChoiceQuestionId,
} from "../../src/provider/decisionsQuestionIds.js";

describe("decisionsQuestionIds (ADR §7.1.2 / A-1 SLOT_ENUM)", () => {
  it("slotChoiceQuestionId uses slot_<SLOT> segments from answerTypes slots", () => {
    expect(slotChoiceQuestionId("TOP")).toBe("slot_TOP");
    expect(parseSlotChoiceQuestionId("slot_FOOTWEAR")).toBe("FOOTWEAR");
  });

  it("parseSlotChoiceQuestionId rejects unknown, reserved and malformed suffixes", () => {
    const invalid = [
      "slot_BOGUS",
      "slot_constructor",
      "slot___proto__",
      "slot_top",
      "slot_",
      "slot_TOP ",
      " slot_TOP",
      "slot_TOP\n",
    ];
    for (const id of invalid) {
      expect(parseSlotChoiceQuestionId(id)).toBeNull();
    }
  });

  it("providerQuestionsMatchSlotIdContract rejects none on required slot options", () => {
    expect(
      providerQuestionsMatchSlotIdContract(
        [
          {
            id: slotChoiceQuestionId("BOTTOM"),
            type: "choice",
            slot: "BOTTOM",
            options: { none: {}, g_1: {} },
          },
        ],
        new Set(["BOTTOM"]),
      ),
    ).toBe(false);
  });

  it("providerQuestionsMatchSlotIdContract rejects duplicate question ids", () => {
    expect(
      providerQuestionsMatchSlotIdContract([
        {
          id: slotChoiceQuestionId("TOP"),
          type: "choice",
          slot: "TOP",
          options: { g_1: {} },
        },
        {
          id: slotChoiceQuestionId("TOP"),
          type: "choice",
          slot: "BOTTOM",
          options: { g_2: {} },
        },
      ]),
    ).toBe(false);
  });

  it("providerQuestionsMatchSlotIdContract requires matching choice ids", () => {
    expect(
      providerQuestionsMatchSlotIdContract([
        {
          id: slotChoiceQuestionId("TOP"),
          type: "choice",
          slot: "TOP",
          options: { g_1: {} },
        },
      ]),
    ).toBe(true);
    expect(
      providerQuestionsMatchSlotIdContract([
        {
          id: "not_slot_TOP",
          type: "choice",
          slot: "TOP",
          options: { g_1: {} },
        },
      ]),
    ).toBe(false);
  });
});

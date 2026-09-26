import { describe, expect, it } from "vitest";
import { slotChoiceQuestionId } from "../../src/provider/decisionsQuestionIds.js";
import { mapDecisionsToAssignments } from "../../src/provider/mapDecisionsToAssignments.js";
import type { ProviderQuestion } from "../../src/provider/types.js";
import { mildWorkContext } from "../stage3/helpers.js";

const SUIT_JACKET = "a1000003-0003-4000-8000-000000000003";
const SUIT_TROUSERS = "a1000005-0005-4000-8000-000000000004";

describe("mapDecisionsToAssignments", () => {
  it("expands a set token to both member slots and ignores the partner question", () => {
    const setToken = "s_suit1";
    const questions: ProviderQuestion[] = [
      {
        id: slotChoiceQuestionId("JACKET"),
        type: "choice",
        slot: "JACKET",
        options: { [setToken]: {} },
      },
      {
        id: slotChoiceQuestionId("BOTTOM"),
        type: "choice",
        slot: "BOTTOM",
        options: { none: {} },
      },
    ];
    const { assignments } = mapDecisionsToAssignments({
      questions,
      answers: {
        [slotChoiceQuestionId("JACKET")]: { type: "choice", choice: setToken },
        [slotChoiceQuestionId("BOTTOM")]: { type: "choice", choice: "none" },
      },
      tokenToGarmentId: {},
      setTokens: [
        {
          token: setToken,
          firstSlot: "JACKET",
          memberGarmentIds: [SUIT_JACKET, SUIT_TROUSERS],
          memberSlots: ["JACKET", "BOTTOM"],
        },
      ],
      seedAssignments: [],
      wardrobe: [],
      context: mildWorkContext(),
      requiredSlots: new Set(),
    });

    const ids = assignments.map((a) => a.garmentId);
    expect(ids).toContain(SUIT_JACKET);
    expect(ids).toContain(SUIT_TROUSERS);
  });

  it("reports noul token when mapped garment is missing from wardrobe", () => {
    const noulId = "noul_belt";
    const token = "g_belt";
    const garmentId = "a1000007-0007-4000-8000-000000000099";
    const { assignments, unknownTokens } = mapDecisionsToAssignments({
      questions: [
        { id: noulId, type: "noul", garmentToken: token },
      ],
      answers: { [noulId]: { type: "noul", noul: 0.9 } },
      tokenToGarmentId: { [token]: garmentId },
      seedAssignments: [],
      wardrobe: [],
      context: mildWorkContext(),
      requiredSlots: new Set(),
    });
    expect(assignments.filter((a) => a.slot === "ACCESSORY")).toHaveLength(0);
    expect(unknownTokens).toContain(token);
  });
});

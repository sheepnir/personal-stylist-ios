import { describe, expect, it } from "vitest";
import { createOwnRecord } from "../../src/provider/safeOwn.js";
import { mergeCautionsLikeGenerateLocal } from "../../src/provider/composeProviderRationale.js";
import { slotChoiceQuestionId } from "../../src/provider/decisionsQuestionIds.js";
import { parseDecisionsResponseBody } from "../../src/provider/parseDecisionsOutput.js";
import { MAX_PROVIDER_RESPONSE_BYTES } from "../../src/provider/constants.js";
import { validateProviderOutput } from "../../src/provider/validateProviderOutput.js";
import type { ValidateProviderOutputInput } from "../../src/provider/types.js";
import {
  pipelineFromScenario,
  stage1InputFromScenario,
} from "../stage3/helpers.js";
import type { OutfitAssignment, Slot } from "../../src/types.js";

const MOCK_MODEL = "mock/stylist-v0";
const SUIT_JACKET = "a1000003-0003-4000-8000-000000000003";
const SUIT_TROUSERS = "a1000005-0005-4000-8000-000000000004";

function decisionsBody(answers: Record<string, unknown>): string {
  return JSON.stringify({
    id: "mock",
    model: MOCK_MODEL,
    provider: "mock",
    answers,
    usage: { input_tokens: 1, output_tokens: 1 },
  });
}

function minimalInput(): ValidateProviderOutputInput {
  const { scenario, stage1, stage2, builder } = pipelineFromScenario(
    "T2-01-sportcoat-mild-work",
  );
  if (!stage1.ok || !stage2 || !builder) throw new Error("pipeline");
  const s1 = stage1InputFromScenario(scenario);
  const topCandidate = stage2.shortlist.TOP?.[0]?.garmentId;
  if (!topCandidate) throw new Error("no TOP shortlist");
  const token = "g_top1";
  const topId = slotChoiceQuestionId("TOP");
  const options = createOwnRecord<unknown>();
  options[token] = {};
  const questions = [
    {
      id: topId,
      type: "choice" as const,
      slot: "TOP" as Slot,
      options,
    },
  ];
  const seedAssignments: OutfitAssignment[] = stage2.fixed.map((f) => ({
    slot: f.slot,
    garmentId: f.garmentId,
    isAnchor: f.role === "anchor",
    isLocked: f.role === "lock",
    gapReason: null,
  }));
  return {
    responseBody: decisionsBody({
      [topId]: { type: "choice", choice: token },
    }),
    expectedModelSlug: MOCK_MODEL,
    questions,
    tokenToGarmentId: Object.assign(createOwnRecord<string>(), {
      [token]: topCandidate,
    }),
    seedAssignments,
    stage4: {
      candidateIds: stage2.candidateIds,
      candidateSet: builder.candidateSet,
      fixed: stage2.fixed,
      wardrobe: s1.wardrobe,
      context: s1.context,
      profile: s1.profile ?? null,
      sets: s1.sets,
      options: s1.options,
    },
    builderInput: {
      wardrobe: s1.wardrobe,
      context: s1.context,
      profile: s1.profile,
      sets: s1.sets,
      options: s1.options,
    },
    stage2,
  };
}

describe("provider hardening (QA / ADR §7.1.3)", () => {
  it("treats __proto__ answer key as a real key (OUTPUT_SCHEMA id mismatch)", () => {
    const input = minimalInput();
    const topId = slotChoiceQuestionId("TOP");
    input.responseBody = `{"model":"${MOCK_MODEL}","usage":{"input_tokens":1,"output_tokens":1},"answers":{"__proto__":{"type":"choice","choice":"evil"},"${topId}":{"type":"choice","choice":"g_top1"}}}`;
    const result = validateProviderOutput(input);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.cause).toBe("OUTPUT_SCHEMA");
  });

  it("rejects constructor and hasOwnProperty choices not in options", () => {
    const input = minimalInput();
    const topId = slotChoiceQuestionId("TOP");
    const opts = createOwnRecord<unknown>();
    opts.g_top1 = {};
    input.questions[0] = { id: topId, type: "choice", slot: "TOP", options: opts };
    input.tokenToGarmentId.g_top1 = input.tokenToGarmentId.g_top1!;
    for (const bad of ["constructor", "hasOwnProperty", "toString"]) {
      input.responseBody = decisionsBody({
        [topId]: { type: "choice", choice: bad },
      });
      const result = validateProviderOutput(input);
      expect(result.ok).toBe(false);
      if (result.ok) return;
      expect(result.cause).toBe("OUTPUT_SCHEMA");
    }
  });

  it("rejects an extra garbage answer id", () => {
    const input = minimalInput();
    const topId = slotChoiceQuestionId("TOP");
    input.responseBody = decisionsBody({
      [topId]: { type: "choice", choice: "g_top1" },
      extra_garbage: { type: "choice", choice: "g_top1" },
    });
    const result = validateProviderOutput(input);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.cause).toBe("OUTPUT_SCHEMA");
  });

  it("rejects prototype-pollution choice keys not offered in options", () => {
    const input = minimalInput();
    const topId = slotChoiceQuestionId("TOP");
    input.questions[0] = {
      id: topId,
      type: "choice",
      slot: "TOP",
      options: createOwnRecord(),
    };
    input.questions[0].options.g_top1 = {};
    input.responseBody = decisionsBody({
      [topId]: { type: "choice", choice: "__proto__" },
    });
    input.tokenToGarmentId.g_top1 = "a1000001-0001-4000-8000-000000000001";
    const result = validateProviderOutput(input);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.cause).toBe("OUTPUT_SCHEMA");
  });

  it("rejects non-string tokenToGarmentId values (OUTPUT_SCHEMA)", () => {
    const input = minimalInput();
    input.tokenToGarmentId.g_top1 = 123 as unknown as string;
    const result = validateProviderOutput(input);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.cause).toBe("OUTPUT_SCHEMA");
  });

  it("per-answer shape errors yield OUTPUT_SCHEMA not OUTPUT_PARSE", () => {
    const input = minimalInput();
    const topId = slotChoiceQuestionId("TOP");
    input.tokenToGarmentId.g_top1 = "a1000001-0001-4000-8000-000000000001";
    input.responseBody = decisionsBody({
      [topId]: "bare-string",
    });
    let result = validateProviderOutput(input);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.cause).toBe("OUTPUT_SCHEMA");

    input.responseBody = decisionsBody({
      [topId]: { type: "choice", choice: 42 },
    });
    result = validateProviderOutput(input);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.cause).toBe("OUTPUT_SCHEMA");
  });

  it("rejects duplicate identical question ids", () => {
    const input = minimalInput();
    const topId = slotChoiceQuestionId("TOP");
    input.questions = [
      { id: topId, type: "choice", slot: "TOP", options: { g_top1: {} } },
      { id: topId, type: "choice", slot: "TOP", options: { g_top1: {} } },
    ];
    input.tokenToGarmentId.g_top1 = "a1000001-0001-4000-8000-000000000001";
    const result = validateProviderOutput(input);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.cause).toBe("OUTPUT_SCHEMA");
  });

  it("rejects set token on wrong slot question", () => {
    const input = minimalInput();
    const setToken = "s_suit";
    const topId = slotChoiceQuestionId("TOP");
    const bottomId = slotChoiceQuestionId("BOTTOM");
    input.questions = [
      {
        id: topId,
        type: "choice",
        slot: "TOP",
        options: { [setToken]: {} },
      },
      {
        id: bottomId,
        type: "choice",
        slot: "BOTTOM",
        options: { none: {} },
      },
    ];
    input.setTokens = [
      {
        token: setToken,
        firstSlot: "JACKET",
        memberGarmentIds: [SUIT_JACKET, SUIT_TROUSERS],
        memberSlots: ["JACKET", "BOTTOM"],
      },
    ];
    input.responseBody = decisionsBody({
      [topId]: { type: "choice", choice: setToken },
      [bottomId]: { type: "choice", choice: "none" },
    });
    const result = validateProviderOutput(input);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.cause).toBe("OUTPUT_SCHEMA");
  });

  it("rejects empty set token members", () => {
    const input = minimalInput();
    const setToken = "s_empty";
    const jacketId = slotChoiceQuestionId("JACKET");
    input.questions = [
      {
        id: jacketId,
        type: "choice",
        slot: "JACKET",
        options: { [setToken]: {} },
      },
    ];
    input.setTokens = [
      {
        token: setToken,
        firstSlot: "JACKET",
        memberGarmentIds: [],
        memberSlots: [],
      },
    ];
    input.responseBody = decisionsBody({
      [jacketId]: { type: "choice", choice: setToken },
    });
    const result = validateProviderOutput(input);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.cause).toBe("OUTPUT_SCHEMA");
  });

  it("rejects none on required slot answer", () => {
    const input = minimalInput();
    const bottomId = slotChoiceQuestionId("BOTTOM");
    input.questions.push({
      id: bottomId,
      type: "choice",
      slot: "BOTTOM",
      options: { none: {}, g_bot: {} },
    });
    input.responseBody = decisionsBody({
      [slotChoiceQuestionId("TOP")]: { type: "choice", choice: "g_top1" },
      [bottomId]: { type: "choice", choice: "none" },
    });
    input.tokenToGarmentId.g_top1 = "a1000001-0001-4000-8000-000000000001";
    const result = validateProviderOutput(input);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.cause).toBe("OUTPUT_SCHEMA");
  });

  it("rejects body over 64KB as OUTPUT_PARSE", () => {
    const input = minimalInput();
    input.responseBody = " ".repeat(MAX_PROVIDER_RESPONSE_BYTES + 1);
    const result = validateProviderOutput(input);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.cause).toBe("OUTPUT_PARSE");
  });

  it("mergeCautionsLikeGenerateLocal keeps at most two cautions", () => {
    const merged = mergeCautionsLikeGenerateLocal(
      ["builder-a", "builder-b", "builder-c"],
      [
        { code: "LAYER_REQUIREMENT", reason: "stage4-a" },
        { code: "RATIONALE_QUALITY", reason: "stage4-b" },
      ],
    );
    expect(merged?.length).toBe(2);
    expect(merged).toEqual(["stage4-a", "stage4-b"]);
  });
});

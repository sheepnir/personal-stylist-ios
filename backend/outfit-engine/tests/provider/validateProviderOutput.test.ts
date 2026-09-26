import { describe, expect, it } from "vitest";
import { rationaleWithinLimits } from "../../src/provider/composeProviderRationale.js";
import { validateProviderOutput } from "../../src/provider/validateProviderOutput.js";
import type {
  ProviderQuestion,
  ProviderSetToken,
  ValidateProviderOutputInput,
} from "../../src/provider/types.js";
import type {
  OutfitAssignment,
  Slot,
  Stage4ViolationCode,
} from "../../src/types.js";
import {
  pipelineFromScenario,
  stage1InputFromScenario,
} from "../stage3/helpers.js";

const MOCK_MODEL = "mock/stylist-v0";
const SPORT_COAT = "a1000003-0003-4000-8000-000000000001";
const SUIT_JACKET = "a1000003-0003-4000-8000-000000000003";
const SUIT_TROUSERS = "a1000005-0005-4000-8000-000000000004";
const JEANS = "a1000005-0005-4000-8000-000000000001";
const FAKE_ID = "ffffffff-ffff-4000-8000-000000000099";

function decisionsBody(
  answers: Record<string, unknown>,
  model = MOCK_MODEL,
): string {
  return JSON.stringify({
    id: "mock-dec-test",
    model,
    provider: "mock",
    answers,
    usage: { input_tokens: 10, output_tokens: 5 },
  });
}

function choiceAnswer(choice: string) {
  return { type: "choice", choice, confidence: 0.9, probabilities: {} };
}

function garmentToken(
  garmentId: string,
  tokenToGarmentId: Record<string, string>,
): string {
  const existing = Object.entries(tokenToGarmentId).find(
    ([, id]) => id === garmentId,
  );
  if (existing) return existing[0];
  const token = `g_${garmentId.replace(/-/g, "").slice(0, 8)}`;
  tokenToGarmentId[token] = garmentId;
  return token;
}

function baseFromScenario(
  scenarioId: string,
  overrides?: Partial<ValidateProviderOutputInput>,
): ValidateProviderOutputInput {
  const { scenario, stage1, stage2, builder } = pipelineFromScenario(scenarioId);
  if (!stage1.ok || !stage2 || !builder) {
    throw new Error(`pipeline failed for ${scenarioId}`);
  }
  const s1 = stage1InputFromScenario(scenario);
  const tokenToGarmentId: Record<string, string> = {};
  const questions: ProviderQuestion[] = [];
  const requireSlots = new Set(s1.options?.requireSlots ?? []);

  for (const [slot, list] of Object.entries(stage2.shortlist) as [
    Slot,
    { garmentId: string }[],
  ][]) {
    const fixedInSlot = stage2.fixed.some(
      (f) => f.slot === slot && f.slot !== "ACCESSORY",
    );
    if (fixedInSlot) continue;
    if (slot === "ACCESSORY") continue;
    const options: Record<string, unknown> = {};
    for (const c of list ?? []) {
      options[garmentToken(c.garmentId, tokenToGarmentId)] = {};
    }
    if (!requireSlots.has(slot)) {
      options.none = {};
    }
    questions.push({
      id: `slot_${slot}`,
      type: "choice",
      options,
      slot,
    });
  }

  const seedAssignments: OutfitAssignment[] = stage2.fixed.map((f) => ({
    slot: f.slot,
    garmentId: f.garmentId,
    isAnchor: f.role === "anchor",
    isLocked: f.role === "lock",
    gapReason: null,
  }));

  const answers: Record<string, unknown> = {};
  for (const q of questions) {
    if (q.type !== "choice") continue;
    const pick = builder.assignments.find(
      (a) => a.slot === q.slot && a.garmentId,
    );
    if (pick?.garmentId) {
      answers[q.id] = choiceAnswer(
        garmentToken(pick.garmentId, tokenToGarmentId),
      );
      continue;
    }
    if ("none" in q.options) {
      answers[q.id] = choiceAnswer("none");
      continue;
    }
    const fallback = Object.keys(q.options).find((k) => k.startsWith("g_"));
    if (fallback) answers[q.id] = choiceAnswer(fallback);
  }

  return {
    responseBody: decisionsBody(answers),
    expectedModelSlug: MOCK_MODEL,
    questions,
    tokenToGarmentId,
    seedAssignments,
    stage4: {
      candidateIds: stage2.candidateIds,
      candidateSet: builder.candidateSet,
      fixed: stage2.fixed,
      wardrobe: s1.wardrobe,
      context: s1.context,
      profile: s1.profile ?? null,
      sets: s1.sets,
      options: {
        requireSlots: s1.options?.requireSlots,
        accessoryPolicy: s1.options?.accessoryPolicy,
      },
    },
    builderInput: {
      wardrobe: s1.wardrobe,
      context: s1.context,
      profile: s1.profile,
      sets: s1.sets,
      options: s1.options,
    },
    stage2,
    excludeGarmentSets: (
      scenario.inputs.options as { excludeGarmentSets?: string[][] } | undefined
    )?.excludeGarmentSets,
    ...overrides,
  };
}

describe("validateProviderOutput — Decisions shape (ADR §7.1.3)", () => {
  it("rejects bad JSON with OUTPUT_PARSE", () => {
    const input = baseFromScenario("T2-01-sportcoat-mild-work");
    input.responseBody = "{not json";
    const result = validateProviderOutput(input);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.cause).toBe("OUTPUT_PARSE");
  });

  it("rejects model mismatch with OUTPUT_MODEL_MISMATCH", () => {
    const input = baseFromScenario("T2-01-sportcoat-mild-work");
    input.responseBody = decisionsBody(
      JSON.parse(input.responseBody).answers,
      "other/model",
    );
    const result = validateProviderOutput(input);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.cause).toBe("OUTPUT_MODEL_MISMATCH");
  });

  it("accepts dated snapshot suffix on model slug", () => {
    const input = baseFromScenario("T2-01-sportcoat-mild-work");
    const answers = JSON.parse(input.responseBody).answers;
    input.responseBody = decisionsBody(answers, `${MOCK_MODEL}-20260926`);
    const result = validateProviderOutput(input);
    expect(result.ok).toBe(true);
  });

  it("rejects missing answer with OUTPUT_SCHEMA", () => {
    const input = baseFromScenario("T2-01-sportcoat-mild-work");
    const parsed = JSON.parse(input.responseBody);
    delete parsed.answers.slot_TOP;
    input.responseBody = JSON.stringify(parsed);
    const result = validateProviderOutput(input);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.cause).toBe("OUTPUT_SCHEMA");
  });

  it("rejects extra answer with OUTPUT_SCHEMA", () => {
    const input = baseFromScenario("T2-01-sportcoat-mild-work");
    const parsed = JSON.parse(input.responseBody);
    parsed.answers.extra_slot = choiceAnswer("g_abcd");
    input.responseBody = JSON.stringify(parsed);
    const result = validateProviderOutput(input);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.cause).toBe("OUTPUT_SCHEMA");
  });

  it("rejects wrong answer type with OUTPUT_SCHEMA", () => {
    const input = baseFromScenario("T2-01-sportcoat-mild-work");
    const parsed = JSON.parse(input.responseBody);
    const firstId = input.questions[0]!.id;
    parsed.answers[firstId] = { type: "noul", noul: 0.5 };
    input.responseBody = JSON.stringify(parsed);
    const result = validateProviderOutput(input);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.cause).toBe("OUTPUT_SCHEMA");
  });

  it("rejects choice not in offered options with OUTPUT_SCHEMA", () => {
    const input = baseFromScenario("T2-01-sportcoat-mild-work");
    const parsed = JSON.parse(input.responseBody);
    const firstId = input.questions[0]!.id;
    parsed.answers[firstId] = choiceAnswer("g_notoffered");
    input.responseBody = JSON.stringify(parsed);
    const result = validateProviderOutput(input);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.cause).toBe("OUTPUT_SCHEMA");
  });

  it("happy path: pipeline-equivalent outfit passes with provider summary", () => {
    const input = baseFromScenario("T2-01-sportcoat-mild-work");
    const result = validateProviderOutput(input);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.rationale.teachingNote).toBeNull();
    expect(result.rationale.summary).toContain("stylist model");
    expect(result.assignments.some((a) => a.garmentId)).toBe(true);
  });

  it("happy path: none on optional slot omits that slot row", () => {
    const input = baseFromScenario("T2-01-sportcoat-mild-work");
    const outerQ = input.questions.find(
      (q) => q.type === "choice" && q.slot === "OUTERWEAR",
    );
    if (!outerQ || outerQ.type !== "choice" || !("none" in outerQ.options)) {
      return;
    }
    const parsed = JSON.parse(input.responseBody);
    parsed.answers[outerQ.id] = choiceAnswer("none");
    input.responseBody = JSON.stringify(parsed);
    const result = validateProviderOutput(input);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.assignments.some((a) => a.slot === "OUTERWEAR")).toBe(false);
  });


  it("rejects unknown garment token with OUTPUT_TOKEN_MAP", () => {
    const input = baseFromScenario("T2-01-sportcoat-mild-work");
    const parsed = JSON.parse(input.responseBody);
    const topQ = input.questions.find(
      (q) => q.type === "choice" && q.slot === "TOP",
    );
    if (!topQ || topQ.type !== "choice") return;
    topQ.options.g_unknown = {};
    parsed.answers[topQ.id] = choiceAnswer("g_unknown");
    input.responseBody = JSON.stringify(parsed);
    const result = validateProviderOutput(input);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.cause).toBe("OUTPUT_TOKEN_MAP");
  });

  it("rejects duplicate outfit in excludeGarmentSets with OUTPUT_EXCLUDED_SET", () => {
    const input = baseFromScenario("T2-01-sportcoat-mild-work");
    const filled = pipelineFromScenario("T2-01-sportcoat-mild-work").builder!
      .assignments.filter((a) => a.garmentId)
      .map((a) => a.garmentId!);
    input.excludeGarmentSets = [filled];
    const result = validateProviderOutput(input);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.cause).toBe("OUTPUT_EXCLUDED_SET");
  });
});

describe("validateProviderOutput — runStage4 violations via mapped answers", () => {
  function expectStage4Code(
    scenarioId: string,
    mutate: (ctx: {
      input: ValidateProviderOutputInput;
      parsed: { answers: Record<string, unknown> };
    }) => void,
    code: Stage4ViolationCode,
  ) {
    const input = baseFromScenario(scenarioId);
    const parsed = JSON.parse(input.responseBody) as {
      answers: Record<string, unknown>;
    };
    mutate({ input, parsed });
    input.responseBody = JSON.stringify({
      ...JSON.parse(input.responseBody),
      answers: parsed.answers,
    });
    const result = validateProviderOutput(input);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.cause).toBe("OUTPUT_STAGE4");
    expect(result.stage4ViolationCodes).toContain(code);
  }

  it("SET_INTEGRITY when only half of a set is chosen", () => {
    const input = baseFromScenario("T2-03-suit-anchor-atomic");
    const bottomQ = input.questions.find(
      (q) => q.type === "choice" && q.slot === "BOTTOM",
    );
    if (!bottomQ || bottomQ.type !== "choice") return;
    const jeansToken = garmentToken(JEANS, input.tokenToGarmentId);
    bottomQ.options[jeansToken] = {};
    const bottomIds = new Set(input.stage4.candidateIds?.BOTTOM ?? []);
    bottomIds.add(JEANS);
    input.stage4.candidateIds = {
      ...input.stage4.candidateIds,
      BOTTOM: [...bottomIds],
    };
    const parsed = JSON.parse(input.responseBody);
    parsed.answers[bottomQ.id] = choiceAnswer(jeansToken);
    input.responseBody = JSON.stringify(parsed);
    const result = validateProviderOutput(input);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.cause).toBe("OUTPUT_STAGE4");
    expect(result.stage4ViolationCodes).toContain("SET_INTEGRITY");
  });

  it("CANDIDATE_SET_MEMBERSHIP for token mapped to out-of-shortlist garment", () => {
    const input = baseFromScenario("T2-01-sportcoat-mild-work");
    const topQ = input.questions.find(
      (q) => q.type === "choice" && q.slot === "TOP",
    );
    if (!topQ || topQ.type !== "choice") return;
    const badToken = "g_fake";
    input.tokenToGarmentId[badToken] = FAKE_ID;
    topQ.options[badToken] = {};
    input.stage4.wardrobe = [
      ...input.stage4.wardrobe,
      {
        id: FAKE_ID,
        displayName: "Fake",
        slot: "TOP",
        availability: "AVAILABLE",
        readiness: "READY",
      },
    ];
    const parsed = JSON.parse(input.responseBody);
    parsed.answers[topQ.id] = choiceAnswer(badToken);
    input.responseBody = JSON.stringify(parsed);
    const result = validateProviderOutput(input);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.cause).toBe("OUTPUT_STAGE4");
    expect(result.stage4ViolationCodes).toContain("CANDIDATE_SET_MEMBERSHIP");
  });

  it("COMBINATION_VIOLATION when jeans paired with sport coat", () => {
    const input = baseFromScenario("T2-01-sportcoat-mild-work");
    const bottomQ = input.questions.find(
      (q) => q.type === "choice" && q.slot === "BOTTOM",
    );
    if (!bottomQ || bottomQ.type !== "choice") return;
    const jeansToken = `g_${JEANS.slice(0, 4)}`;
    input.tokenToGarmentId[jeansToken] = JEANS;
    bottomQ.options[jeansToken] = {};
    input.stage4.profile = {
      ...(input.stage4.profile ?? {}),
      activeRules: [
        {
          id: "combo-test",
          kind: "COMBINATION",
          polarity: "DISLIKE",
          subject: { pair: [SPORT_COAT, JEANS] },
          scope: "ALWAYS",
          active: true,
        },
      ],
    };
    const parsed = JSON.parse(input.responseBody);
    parsed.answers[bottomQ.id] = choiceAnswer(jeansToken);
    input.responseBody = JSON.stringify(parsed);
    const result = validateProviderOutput(input);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.stage4ViolationCodes).toContain("COMBINATION_VIOLATION");
  });
});

describe("rationaleWithinLimits", () => {
  it("flags overlong summary for OUTPUT_LENGTH guard", () => {
    expect(
      rationaleWithinLimits({
        summary: "x".repeat(201),
        teachingNote: null,
      }),
    ).toBe(false);
  });
});

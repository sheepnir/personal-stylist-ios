import { describe, expect, it } from "vitest";
import { runStage4 } from "../../src/stage4/runStage4.js";
import {
  generateLocal,
  isLocalProblem,
} from "../../src/pipeline/generateLocal.js";
import type {
  OutfitAssignment,
  PreferenceRule,
  Stage4Input,
  Stage4ViolationCode,
} from "../../src/types.js";
import {
  pipelineFromScenario,
  loadGarments,
  stage1InputFromScenario,
  loadScenario,
} from "../stage3/helpers.js";

const SPORT_COAT = "a1000003-0003-4000-8000-000000000001";
const SUIT_JACKET = "a1000003-0003-4000-8000-000000000003";
const SUIT_TROUSERS = "a1000005-0005-4000-8000-000000000004";
const JEANS = "a1000005-0005-4000-8000-000000000001";
const BELT = "a1000007-0007-4000-8000-000000000001";
const TIE = "a1000007-0007-4000-8000-000000000002";
const SCARF = "a1000007-0007-4000-8000-000000000003";
const WATCH = "a1000007-0007-4000-8000-000000000004";
const FAKE_ID = "ffffffff-ffff-4000-8000-000000000099";

function hasCode(
  result: { ok: boolean; violations?: { code: Stage4ViolationCode }[] },
  code: Stage4ViolationCode,
): boolean {
  return !!result.violations?.some((v) => v.code === code);
}

function baseInputFromPipeline(id: string): Stage4Input {
  const { scenario, stage1, stage2, builder } = pipelineFromScenario(id);
  if (!stage1.ok || !stage2 || !builder) {
    throw new Error(`pipeline failed for ${id}`);
  }
  const s1 = stage1InputFromScenario(scenario);
  return {
    assignments: structuredClone(builder.assignments) as OutfitAssignment[],
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
    rationale: builder.rationale,
  };
}

describe("Stage 4 outfit validator (M0-19)", () => {
  it("happy path: T2-01 pipeline outfit passes", () => {
    const input = baseInputFromPipeline("T2-01-sportcoat-mild-work");
    const result = runStage4(input);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    for (const c of result.cautions) {
      expect(["RATIONALE_QUALITY", "LAYER_REQUIREMENT"]).toContain(c.code);
    }
  });

  it("rejects half keepTogether set (SET_INTEGRITY)", () => {
    const input = baseInputFromPipeline("T2-03-suit-anchor-atomic");
    input.assignments = input.assignments.filter(
      (a) => a.garmentId !== SUIT_TROUSERS,
    );
    const result = runStage4(input);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(hasCode(result, "SET_INTEGRITY")).toBe(true);
    expect(
      result.violations.some((v) => v.relatedIds?.includes(SUIT_JACKET)),
    ).toBe(true);
  });

  it("rejects missing lock (LOCK_MISSING)", () => {
    const input = baseInputFromPipeline("T2-03-suit-anchor-atomic");
    input.assignments = input.assignments.filter((a) => a.slot !== "BOTTOM");
    const result = runStage4(input);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(
      hasCode(result, "LOCK_MISSING") || hasCode(result, "LOCK_MISMATCH"),
    ).toBe(true);
  });

  it("rejects combination violation on completed outfit", () => {
    const input = baseInputFromPipeline("T2-01-sportcoat-mild-work");
    input.assignments = input.assignments.map((a) =>
      a.slot === "BOTTOM"
        ? { ...a, garmentId: JEANS, gapReason: null }
        : a,
    );
    const bottomIds = new Set(input.candidateIds?.BOTTOM ?? []);
    bottomIds.add(JEANS);
    input.candidateIds = { ...input.candidateIds, BOTTOM: [...bottomIds] };

    const comboRule: PreferenceRule = {
      id: "test-combo-sportcoat-jeans",
      kind: "COMBINATION",
      polarity: "DISLIKE",
      subject: { pair: [SPORT_COAT, JEANS] },
      scope: "ALWAYS",
      active: true,
    };
    input.profile = {
      ...(input.profile ?? {}),
      activeRules: [...(input.profile?.activeRules ?? []), comboRule],
    };

    const result = runStage4(input);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(hasCode(result, "COMBINATION_VIOLATION")).toBe(true);
  });

  it("rejects duplicate non-ACCESSORY slot", () => {
    const input = baseInputFromPipeline("T2-01-sportcoat-mild-work");
    input.assignments.push({
      slot: "TOP",
      garmentId: FAKE_ID,
      isAnchor: false,
      isLocked: false,
      gapReason: null,
    });
    input.candidateIds = {
      ...input.candidateIds,
      TOP: [...(input.candidateIds?.TOP ?? []), FAKE_ID],
    };
    input.wardrobe = [
      ...input.wardrobe,
      {
        id: FAKE_ID,
        displayName: "Fake Top",
        slot: "TOP",
        category: "shirt",
        availability: "AVAILABLE",
        readiness: "READY",
      },
    ];

    const dup = runStage4(input);
    expect(dup.ok).toBe(false);
    if (dup.ok) return;
    expect(hasCode(dup, "SLOT_UNIQUENESS")).toBe(true);
  });

  it("rejects more than 3 accessories (ACCESSORY_LIMIT)", () => {
    const input = baseInputFromPipeline("T2-01-sportcoat-mild-work");
    const accIds = [BELT, TIE, SCARF, WATCH];
    for (const id of accIds) {
      input.assignments.push({
        slot: "ACCESSORY",
        garmentId: id,
        isAnchor: false,
        isLocked: false,
        gapReason: null,
      });
    }
    input.candidateIds = {
      ...input.candidateIds,
      ACCESSORY: accIds,
    };
    input.options = { ...input.options, accessoryPolicy: "OPEN" };

    const tooMany = runStage4(input);
    expect(tooMany.ok).toBe(false);
    if (tooMany.ok) return;
    expect(
      hasCode(tooMany, "ACCESSORY_LIMIT") ||
        hasCode(tooMany, "ACCESSORY_POLICY"),
    ).toBe(true);
  });

  it("rejects garment id not in candidate set", () => {
    const input = baseInputFromPipeline("T2-01-sportcoat-mild-work");
    input.assignments = input.assignments.map((a) =>
      a.slot === "TOP" ? { ...a, garmentId: FAKE_ID, gapReason: null } : a,
    );
    input.candidateIds = {
      ...input.candidateIds,
      TOP: (input.candidateIds?.TOP ?? []).filter((id) => id !== FAKE_ID),
    };
    input.wardrobe = [
      ...input.wardrobe,
      {
        id: FAKE_ID,
        displayName: "Invented Shirt",
        slot: "TOP",
        category: "shirt",
        availability: "AVAILABLE",
        readiness: "READY",
      },
    ];

    const result = runStage4(input);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(hasCode(result, "CANDIDATE_SET_MEMBERSHIP")).toBe(true);
  });

  it("accessoryPolicy LOCKED rejects extras", () => {
    const input = baseInputFromPipeline("T2-01-sportcoat-mild-work");
    input.fixed = [
      ...input.fixed,
      { garmentId: BELT, slot: "ACCESSORY", role: "lock" },
    ];
    input.options = { ...input.options, accessoryPolicy: "LOCKED" };
    input.assignments = [
      ...input.assignments,
      {
        slot: "ACCESSORY",
        garmentId: BELT,
        isAnchor: false,
        isLocked: true,
        gapReason: null,
      },
      {
        slot: "ACCESSORY",
        garmentId: TIE,
        isAnchor: false,
        isLocked: false,
        gapReason: null,
      },
    ];
    input.candidateIds = {
      ...input.candidateIds,
      ACCESSORY: [BELT, TIE],
    };

    const result = runStage4(input);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(hasCode(result, "ACCESSORY_POLICY")).toBe(true);
  });

  it("accessoryPolicy LOCKED accepts exact locked accessories", () => {
    const input = baseInputFromPipeline("T2-01-sportcoat-mild-work");
    input.fixed = [
      ...input.fixed,
      { garmentId: BELT, slot: "ACCESSORY", role: "lock" },
    ];
    input.options = { ...input.options, accessoryPolicy: "LOCKED" };
    input.assignments = [
      ...input.assignments,
      {
        slot: "ACCESSORY",
        garmentId: BELT,
        isAnchor: false,
        isLocked: true,
        gapReason: null,
      },
    ];
    input.candidateIds = {
      ...input.candidateIds,
      ACCESSORY: [BELT],
    };

    const result = runStage4(input);
    expect(result.ok).toBe(true);
  });
});

describe("Stage 4 via generateLocal (optional pipeline asserts)", () => {
  function runScenario(id: string) {
    const scenario = loadScenario(id);
    const s1 = stage1InputFromScenario(scenario);
    return generateLocal({
      wardrobe: s1.wardrobe,
      context: s1.context,
      anchorGarmentId: s1.anchorGarmentId,
      lockedAssignments: s1.lockedAssignments,
      options: s1.options,
      profile: s1.profile,
      sets: s1.sets,
    });
  }

  it("T2-05: complete outfit; no olive-family ids", () => {
    const result = runScenario("T2-05-dislike-olive");
    expect(isLocalProblem(result)).toBe(false);
    if (isLocalProblem(result)) return;
    const byId = new Map(loadGarments().map((g) => [g.id, g]));
    for (const a of result.assignments) {
      if (!a.garmentId) continue;
      const fam = byId.get(a.garmentId)?.colorPrimary?.family?.toLowerCase();
      expect(fam).not.toBe("olive");
    }
  });

  it("T2-07: draft id never appears in assignments", () => {
    const scenario = loadScenario("T2-07-draft-excluded");
    const result = runScenario("T2-07-draft-excluded");
    expect(isLocalProblem(result)).toBe(false);
    if (isLocalProblem(result)) return;
    const drafts = new Set(scenario.inputs.local_drafts ?? []);
    for (const a of result.assignments) {
      if (a.garmentId) expect(drafts.has(a.garmentId)).toBe(false);
    }
  });

  it("T2-09: jeans anchor retained; other pieces formality ≥ 3", () => {
    const result = runScenario("T2-09-jeans-client-formality");
    expect(isLocalProblem(result)).toBe(false);
    if (isLocalProblem(result)) return;
    const byId = new Map(loadGarments().map((g) => [g.id, g]));
    const jeans = result.assignments.find((a) => a.isAnchor);
    expect(jeans?.garmentId).toBeTruthy();
    for (const a of result.assignments) {
      if (!a.garmentId || a.isAnchor) continue;
      const f = byId.get(a.garmentId)?.formality;
      if (f != null) expect(f).toBeGreaterThanOrEqual(3);
    }
  });

  it("T2-11: no laundry-excluded ids in assignments", () => {
    const result = runScenario("T2-11-half-laundry");
    expect(isLocalProblem(result)).toBe(false);
    if (isLocalProblem(result)) return;
    const laundry = new Set(
      loadGarments()
        .filter((g) => String(g.availability).toUpperCase() === "LAUNDRY")
        .map((g) => g.id),
    );
    for (const a of result.assignments) {
      if (a.garmentId) expect(laundry.has(a.garmentId)).toBe(false);
    }
  });

  it("T2-17: COLD with no OUTERWEAR emits LAYER_REQUIREMENT caution", () => {
    const scenario = loadScenario("T2-17-daily-cold");
    const s1 = stage1InputFromScenario(scenario);
    const result = generateLocal({
      wardrobe: s1.wardrobe.filter((g) => g.slot !== "OUTERWEAR"),
      context: s1.context,
      anchorGarmentId: s1.anchorGarmentId,
      lockedAssignments: s1.lockedAssignments,
      options: s1.options,
      profile: s1.profile,
      sets: s1.sets,
    });
    expect(isLocalProblem(result)).toBe(false);
    if (isLocalProblem(result)) return;
    const cautions = result.rationale?.cautions ?? [];
    expect(cautions.length).toBeGreaterThan(0);
    const hasLayerCaution = cautions.some(
      (c) =>
        c.toLowerCase().includes("outerwear") ||
        c.toLowerCase().includes("layer"),
    );
    expect(hasLayerCaution).toBe(true);
  });
});

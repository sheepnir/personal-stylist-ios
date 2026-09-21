import { describe, expect, it } from "vitest";
import { runBuilder } from "../../src/stage3/runBuilder.js";
import { DEFAULT_BUILDER_CONFIG } from "../../src/stage3/config.js";
import { DEFAULT_SCORING_CONFIG } from "../../src/stage2/config.js";
import type {
  BuilderInput,
  GarmentSummary,
  PreferenceRule,
  ScoredCandidate,
  Slot,
  Stage2Result,
} from "../../src/types.js";
import {
  WEIGHTS_VERSION,
  assignmentMap,
  filledIds,
  loadGarments,
  mildWorkContext,
  pipelineFromScenario,
} from "./helpers.js";

const SPORT_COAT = "a1000003-0003-4000-8000-000000000001";
const SUIT_JACKET = "a1000003-0003-4000-8000-000000000003";
const SUIT_TROUSERS = "a1000005-0005-4000-8000-000000000004";
const JEANS = "a1000005-0005-4000-8000-000000000001";
const NAVY_SUIT_SET = "b2000001-0001-4000-8000-000000000001";
const OUTERWEAR_COAT = "a1000004-0004-4000-8000-000000000001";
const MID_LAYER = "a1000002-0002-4000-8000-000000000001";

describe("Stage 3 deterministic builder (M0-16)", () => {
  it("pins weightsVersion 1.0.0 and accessories default off", () => {
    expect(DEFAULT_SCORING_CONFIG.weightsVersion).toBe(WEIGHTS_VERSION);
    expect(DEFAULT_BUILDER_CONFIG.fillOptionalAccessories).toBe(false);
  });

  it("T2-01: complete outfit — sport coat anchor; core slots filled; no OUTERWEAR; formality ∈ [2,4]", () => {
    const { stage1, stage2, builder, scenario } = pipelineFromScenario(
      "T2-01-sportcoat-mild-work",
    );
    expect(stage1.ok).toBe(true);
    expect(builder).toBeDefined();
    expect(stage2!.meta.weightsVersion).toBe(WEIGHTS_VERSION);
    expect(builder!.builderMeta.weightsVersion).toBe(WEIGHTS_VERSION);
    expect(builder!.generation.fallbackLevel).toBe("DETERMINISTIC");
    expect(builder!.generation.modelId).toBe("deterministic-v0");

    const map = assignmentMap(builder!);
    expect(map.JACKET).toBe(SPORT_COAT);
    expect(map.TOP).toBeTruthy();
    expect(map.BOTTOM).toBeTruthy();
    expect(map.FOOTWEAR).toBeTruthy();
    expect(map.OUTERWEAR).toBeUndefined();

    const expected = scenario.expected.complete_outfit as Record<string, string>;
    // Snapshot under default scoring (pin weightsVersion)
    expect(map.TOP).toBe(expected.TOP);
    expect(map.BOTTOM).toBe(expected.BOTTOM);
    expect(map.FOOTWEAR).toBe(expected.FOOTWEAR);

    const byId = new Map(loadGarments().map((g) => [g.id, g]));
    const [lo, hi] = scenario.expected.formality_range as [number, number];
    for (const id of filledIds(builder!)) {
      const g = byId.get(id);
      if (g?.formality != null) {
        expect(g.formality).toBeGreaterThanOrEqual(lo);
        expect(g.formality).toBeLessThanOrEqual(hi);
      }
    }
    // No accessories pulled by default
    expect(
      builder!.assignments.filter((a) => a.slot === "ACCESSORY" && a.garmentId),
    ).toHaveLength(0);
  });

  it("T2-02: FOOTWEAR gap with availability reason; other required filled; no LAUNDRY ids", () => {
    const { builder, stage1 } = pipelineFromScenario("T2-02-footwear-gap");
    expect(stage1.ok).toBe(true);
    expect(builder).toBeDefined();
    const fw = builder!.assignments.find((a) => a.slot === "FOOTWEAR");
    expect(fw?.garmentId ?? null).toBeNull();
    expect(fw?.gapReason).toMatch(/AVAILABLE|availability|FOOTWEAR/i);
    expect(fw!.gapReason!.length).toBeLessThanOrEqual(120);

    const map = assignmentMap(builder!);
    expect(map.JACKET).toBe(SPORT_COAT);
    expect(map.TOP).toBeTruthy();
    expect(map.BOTTOM).toBeTruthy();

    const laundryIds = loadGarments()
      .filter((g) => String(g.availability).toUpperCase() === "LAUNDRY")
      .map((g) => g.id);
    for (const id of filledIds(builder!)) {
      expect(laundryIds).not.toContain(id);
    }
  });

  it("T2-03: suit jacket + trousers both present; TOP filled; never half suit", () => {
    const { builder, stage1 } = pipelineFromScenario(
      "T2-03-suit-anchor-atomic",
    );
    expect(stage1.ok).toBe(true);
    const ids = filledIds(builder!);
    expect(ids).toContain(SUIT_JACKET);
    expect(ids).toContain(SUIT_TROUSERS);
    const map = assignmentMap(builder!);
    expect(map.TOP).toBeTruthy();
    expect(map.FOOTWEAR).toBeTruthy();
    // Half-suit refusal: both or neither — here both (fixed)
    expect(Boolean(map.JACKET) && Boolean(map.BOTTOM)).toBe(true);
  });

  it("T2-04: SET_CONFLICT — builder never called (Stage1 Problem)", () => {
    const { stage1, builder } = pipelineFromScenario(
      "T2-04-set-conflict-partner-laundry",
    );
    expect(stage1.ok).toBe(false);
    if (!stage1.ok) {
      expect(stage1.code).toBe("SET_CONFLICT");
      expect(stage1.detail).toMatch(/trousers|LAUNDRY|partner/i);
    }
    expect(builder).toBeUndefined();
  });

  it("T2-06: coat fixed → jeans absent from BOTTOM; at most one of forbidden pair", () => {
    const { builder, stage2 } = pipelineFromScenario(
      "T2-06-combination-rule",
    );
    expect(builder).toBeDefined();
    const map = assignmentMap(builder!);
    expect(map.JACKET).toBe(SPORT_COAT);
    expect(map.BOTTOM).not.toBe(JEANS);
    expect(map.BOTTOM).toBeTruthy();
    const ids = new Set(filledIds(builder!));
    expect(ids.has(SPORT_COAT) && ids.has(JEANS)).toBe(false);
    expect(stage2!.excludedByCombination.some((e) => e.garmentId === JEANS)).toBe(
      true,
    );
  });

  it("T2-08: COLD — JACKET=anchor AND OUTERWEAR present (layer requirement)", () => {
    const { builder, scenario } = pipelineFromScenario("T2-08-cold-two-layer");
    expect(builder).toBeDefined();
    const map = assignmentMap(builder!);
    expect(map.JACKET).toBe(SPORT_COAT);
    expect(map.OUTERWEAR).toBeTruthy();
    expect(map.OUTERWEAR).toBe(OUTERWEAR_COAT);
    const must = scenario.expected.must_include as string[];
    for (const id of must) {
      expect(filledIds(builder!)).toContain(id);
    }
    // Optional mid-layer on COLD
    expect(map.MID_LAYER).toBe(MID_LAYER);
  });

  it("T2-10: LOCK_CONFLICT — builder never called", () => {
    const { stage1, builder } = pipelineFromScenario("T2-10-lock-conflict");
    expect(stage1.ok).toBe(false);
    if (!stage1.ok) expect(stage1.code).toBe("LOCK_CONFLICT");
    expect(builder).toBeUndefined();
  });

  it("T2-12: set atomic — if suit jacket chosen, trousers chosen; over-cap partner usable", () => {
    const { builder, stage2 } = pipelineFromScenario(
      "T2-12-set-shortlist-over-cap",
      { force_weak_bottom_score_for: SUIT_TROUSERS },
    );
    expect(builder).toBeDefined();
    expect(
      (stage2!.shortlist.BOTTOM ?? []).some(
        (c) =>
          c.garmentId === SUIT_TROUSERS && c.overCapReason === "SET_PARTNER",
      ),
    ).toBe(true);

    const ids = new Set(filledIds(builder!));
    const jacketChosen = ids.has(SUIT_JACKET);
    const trousersChosen = ids.has(SUIT_TROUSERS);
    if (jacketChosen || trousersChosen) {
      expect(jacketChosen && trousersChosen).toBe(true);
    }
    // Core slots filled
    const map = assignmentMap(builder!);
    expect(map.TOP).toBeTruthy();
    expect(map.BOTTOM).toBeTruthy();
    expect(map.FOOTWEAR).toBeTruthy();
  });

  it("synthetic: free–free combo — top BOTTOM clashes with chosen TOP → skip to alternate", () => {
    const topA = "syn-top-a";
    const topB = "syn-top-b";
    const bottomBad = "syn-bottom-bad";
    const bottomGood = "syn-bottom-good";
    const shoe = "syn-shoe";

    const wardrobe: GarmentSummary[] = [
      { id: topA, displayName: "Top A", slot: "TOP", colorPrimary: { family: "navy" }, formality: 3, warmth: 2 },
      { id: topB, displayName: "Top B", slot: "TOP", colorPrimary: { family: "white" }, formality: 3, warmth: 2 },
      { id: bottomBad, displayName: "Bad Bottom", slot: "BOTTOM", colorPrimary: { family: "olive" }, formality: 3, warmth: 2 },
      { id: bottomGood, displayName: "Good Bottom", slot: "BOTTOM", colorPrimary: { family: "grey" }, formality: 3, warmth: 2 },
      { id: shoe, displayName: "Shoe", slot: "FOOTWEAR", colorPrimary: { family: "brown" }, formality: 3, warmth: 2 },
    ];

    const rules: PreferenceRule[] = [
      {
        kind: "COMBINATION",
        polarity: "DISLIKE",
        subject: { pair: [topA, bottomBad] },
        scope: "ALWAYS",
        active: true,
        id: "syn-combo",
      },
    ];

    const stage2 = syntheticStage2(
      {
        TOP: [scored(topA, "TOP", 10), scored(topB, "TOP", 5)],
        BOTTOM: [scored(bottomBad, "BOTTOM", 10), scored(bottomGood, "BOTTOM", 5)],
        FOOTWEAR: [scored(shoe, "FOOTWEAR", 10)],
      },
      [],
    );
    const input: BuilderInput = {
      wardrobe,
      context: mildWorkContext(),
      profile: { activeRules: rules },
      options: { requireSlots: ["TOP", "BOTTOM", "FOOTWEAR"] },
      sets: [],
    };
    const result = runBuilder(stage2, input);
    const map = assignmentMap(result);
    expect(map.TOP).toBe(topA);
    expect(map.BOTTOM).toBe(bottomGood);
    expect(map.FOOTWEAR).toBe(shoe);
    expect(
      result.builderMeta.skipped.some(
        (s) => s.garmentId === bottomBad && s.reason === "COMBINATION",
      ),
    ).toBe(true);
  });

  it("synthetic: COLD OUTERWEAR shortlist empty → gap OUTERWEAR; other slots filled", () => {
    const top = "cold-top";
    const bottom = "cold-bottom";
    const shoe = "cold-shoe";
    const jacket = "cold-jacket";
    const wardrobe: GarmentSummary[] = [
      { id: top, displayName: "Top", slot: "TOP", formality: 3, warmth: 3 },
      { id: bottom, displayName: "Bottom", slot: "BOTTOM", formality: 3, warmth: 3 },
      { id: shoe, displayName: "Shoe", slot: "FOOTWEAR", formality: 3, warmth: 3 },
      { id: jacket, displayName: "Jacket", slot: "JACKET", formality: 3, warmth: 3 },
    ];
    const stage2 = syntheticStage2(
      {
        TOP: [scored(top, "TOP", 10)],
        BOTTOM: [scored(bottom, "BOTTOM", 10)],
        FOOTWEAR: [scored(shoe, "FOOTWEAR", 10)],
      },
      [{ garmentId: jacket, slot: "JACKET", role: "anchor" }],
    );
    const input: BuilderInput = {
      wardrobe,
      context: {
        occasion: "WORK_STANDARD",
        occasionFormality: 3,
        temperatureBand: "COLD",
        precipitation: false,
      },
      options: { requireSlots: ["TOP", "BOTTOM", "FOOTWEAR", "OUTERWEAR"] },
      sets: [],
    };
    const result = runBuilder(stage2, input);
    const ow = result.assignments.find((a) => a.slot === "OUTERWEAR");
    expect(ow?.garmentId ?? null).toBeNull();
    expect(ow?.gapReason).toMatch(/OUTERWEAR|COLD|layer/i);
    const map = assignmentMap(result);
    expect(map.TOP).toBe(top);
    expect(map.BOTTOM).toBe(bottom);
    expect(map.FOOTWEAR).toBe(shoe);
    expect(map.JACKET).toBe(jacket);
  });

  it("determinism: identical inputs → byte-identical assignments + outfitId", () => {
    const a = pipelineFromScenario("T2-01-sportcoat-mild-work");
    const b = pipelineFromScenario("T2-01-sportcoat-mild-work");
    expect(a.builder!.assignments).toEqual(b.builder!.assignments);
    expect(a.builder!.outfitId).toBe(b.builder!.outfitId);
    expect(a.builder!.builderMeta.weightsVersion).toBe(WEIGHTS_VERSION);
  });

  it("zero network: builder module has no fetch / OpenRouter references", async () => {
    const { readFileSync, readdirSync } = await import("node:fs");
    const { dirname, join } = await import("node:path");
    const { fileURLToPath } = await import("node:url");
    const dir = join(dirname(fileURLToPath(import.meta.url)), "../../src/stage3");
    const files = readdirSync(dir).filter((f) => f.endsWith(".ts"));
    expect(files.length).toBeGreaterThan(0);
    for (const f of files) {
      const src = readFileSync(join(dir, f), "utf8");
      expect(src).not.toMatch(/openrouter|fetch\s*\(|axios|http\.request/i);
    }
  });

  it("#28: WORK-scoped combo rule blocks candidate in builder on WORK_STANDARD", () => {
    const wardrobe = loadGarments();
    const sportCoat = wardrobe.find((g) => g.id === SPORT_COAT)!;
    const jeans = wardrobe.find((g) => g.id === JEANS)!;
    expect(sportCoat).toBeDefined();
    expect(jeans).toBeDefined();

    // WORK-scoped rule: sport coat + jeans forbidden
    const workRule: PreferenceRule = {
      id: "work-scoped-test",
      kind: "COMBINATION",
      polarity: "AVOID_HARD",
      subject: {
        pair: [SPORT_COAT, JEANS],
      },
      scope: "WORK",
      provenance: "CONFIRMED",
      active: true,
    };

    const stage2 = syntheticStage2(
      {
        BOTTOM: [scored(JEANS, "BOTTOM", 0.8)],
      },
      [{ garmentId: SPORT_COAT, slot: "JACKET", role: "anchor" }],
    );

    const input: BuilderInput = {
      wardrobe,
      context: { ...mildWorkContext(), occasion: "WORK_STANDARD" },
      profile: {
        version: 1,
        summaryText: "Test",
        activeRules: [workRule],
      },
      sets: [],
      options: { requireSlots: ["JACKET", "BOTTOM"] },
      asOfDate: "2026-09-18",
    };

    const builder = runBuilder(stage2, input);
    const map = assignmentMap(builder);
    // Jeans should be excluded due to WORK-scoped combination rule
    expect(map.BOTTOM).not.toBe(JEANS);
  });

  it("#28: WORK-scoped combo rule does NOT block on CASUAL_DAY", () => {
    const wardrobe = loadGarments();
    const sportCoat = wardrobe.find((g) => g.id === SPORT_COAT)!;
    const jeans = wardrobe.find((g) => g.id === JEANS)!;

    const workRule: PreferenceRule = {
      id: "work-scoped-test",
      kind: "COMBINATION",
      polarity: "AVOID_HARD",
      subject: {
        pair: [SPORT_COAT, JEANS],
      },
      scope: "WORK",
      provenance: "CONFIRMED",
      active: true,
    };

    const stage2 = syntheticStage2(
      {
        BOTTOM: [scored(JEANS, "BOTTOM", 0.8)],
      },
      [{ garmentId: SPORT_COAT, slot: "JACKET", role: "anchor" }],
    );

    const input: BuilderInput = {
      wardrobe,
      context: { ...mildWorkContext(), occasion: "CASUAL_DAY" },
      profile: {
        version: 1,
        summaryText: "Test",
        activeRules: [workRule],
      },
      sets: [],
      options: { requireSlots: ["JACKET", "BOTTOM"] },
      asOfDate: "2026-09-18",
    };

    const builder = runBuilder(stage2, input);
    const map = assignmentMap(builder);
    // On CASUAL_DAY, WORK-scoped rule should not apply, so jeans can be picked
    expect(map.BOTTOM).toBe(JEANS);
  });
});

function scored(
  garmentId: string,
  slot: Slot,
  score: number,
): ScoredCandidate {
  return {
    garmentId,
    slot,
    score,
    breakdown: {
      components: {},
      weighted: {},
      total: score,
    },
  };
}

function syntheticStage2(
  shortlist: Partial<Record<Slot, ScoredCandidate[]>>,
  fixed: Stage2Result["fixed"],
): Stage2Result {
  const candidateIds: Stage2Result["candidateIds"] = {};
  const scores: Stage2Result["scores"] = {};
  for (const [slot, list] of Object.entries(shortlist) as [
    Slot,
    ScoredCandidate[],
  ][]) {
    candidateIds[slot] = list.map((c) => c.garmentId);
    for (const c of list) scores[c.garmentId] = c.breakdown;
  }
  return {
    ok: true,
    shortlist,
    candidateIds,
    scores,
    excludedByCombination: [],
    setShortlistExpansions: [],
    fixed,
    gaps: [],
    relaxationsApplied: [],
    meta: {
      capUsed: 8,
      boldness: "SLIGHT_STRETCH",
      weightsVersion: WEIGHTS_VERSION,
    },
  };
}

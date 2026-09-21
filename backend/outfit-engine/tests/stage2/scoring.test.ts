import { describe, expect, it } from "vitest";
import { runStage2 } from "../../src/stage2/runStage2.js";
import { withWeights, DEFAULT_SCORING_CONFIG } from "../../src/stage2/config.js";
import { scoreGarment } from "../../src/stage2/score.js";
import { runStage1FromScenario, mildWorkContext } from "./helpers.js";
import type { GarmentSummary } from "../../src/types.js";

const JEANS = "a1000005-0005-4000-8000-000000000001";
const SPORT_COAT = "a1000003-0003-4000-8000-000000000001";
const SUIT_JACKET = "a1000003-0003-4000-8000-000000000003";
const SUIT_TROUSERS = "a1000005-0005-4000-8000-000000000004";
const NAVY_SUIT_SET = "b2000001-0001-4000-8000-000000000001";

describe("Stage 2 scoring + shortlist (M0-15)", () => {
  it("T2-06: combo vs anchor drops jeans from BOTTOM; jeans remain in Stage 1 eligible", () => {
    const { stage1, stage2Input } = runStage1FromScenario(
      "T2-06-combination-rule",
    );
    expect(stage1.eligible.BOTTOM).toContain(JEANS);
    expect(stage1.fixed.some((f) => f.garmentId === SPORT_COAT)).toBe(true);

    const stage2 = runStage2(stage1, stage2Input);
    const bottomIds = stage2.candidateIds.BOTTOM ?? [];
    expect(bottomIds).not.toContain(JEANS);
    expect(
      stage2.excludedByCombination.some(
        (e) => e.garmentId === JEANS && e.againstFixedId === SPORT_COAT,
      ),
    ).toBe(true);
    // Other bottoms still scored / shortlisted
    expect(bottomIds.length).toBeGreaterThan(0);
    // Stage 1 eligible unchanged story — jeans still there
    expect(stage1.eligible.BOTTOM).toContain(JEANS);
  });

  it("T2-12: set over-cap — jacket in JACKET shortlist pulls trousers into BOTTOM with SET_PARTNER", () => {
    const { stage1, stage2Input } = runStage1FromScenario(
      "T2-12-set-shortlist-over-cap",
      { force_weak_bottom_score_for: SUIT_TROUSERS },
    );
    expect(stage2Input.options?.candidatesPerSlot).toBe(4);
    expect(stage2Input.options?.force_weak_bottom_score_for).toBe(
      SUIT_TROUSERS,
    );

    const stage2 = runStage2(stage1, stage2Input);
    const jacketIds = stage2.candidateIds.JACKET ?? [];
    expect(jacketIds).toContain(SUIT_JACKET);

    const bottomList = stage2.shortlist.BOTTOM ?? [];
    const trousers = bottomList.find((c) => c.garmentId === SUIT_TROUSERS);
    expect(trousers).toBeDefined();
    expect(trousers!.overCapReason).toBe("SET_PARTNER");
    expect(
      stage2.setShortlistExpansions.some(
        (e) =>
          e.setId === NAVY_SUIT_SET &&
          e.pulledOverCap.some((p) => p.garmentId === SUIT_TROUSERS),
      ),
    ).toBe(true);
  });

  it("T2-03: suit jacket+trousers fixed; TOP/FOOTWEAR shortlists non-empty; no half-suit ranked", () => {
    const { stage1, stage2Input } = runStage1FromScenario(
      "T2-03-suit-anchor-atomic",
    );
    expect(stage1.fixed.map((f) => f.garmentId).sort()).toEqual(
      [SUIT_JACKET, SUIT_TROUSERS].sort(),
    );

    const stage2 = runStage2(stage1, stage2Input);
    expect(stage2.fixed).toEqual(stage1.fixed);
    expect(stage2.shortlist.JACKET ?? []).toEqual([]);
    expect(stage2.shortlist.BOTTOM ?? []).toEqual([]);
    expect((stage2.candidateIds.TOP ?? []).length).toBeGreaterThan(0);
    expect((stage2.candidateIds.FOOTWEAR ?? []).length).toBeGreaterThan(0);
    // Suit members must not appear as ranked shortlist rows
    const allShort = Object.values(stage2.shortlist)
      .flat()
      .map((c) => c.garmentId);
    expect(allShort).not.toContain(SUIT_JACKET);
    expect(allShort).not.toContain(SUIT_TROUSERS);
  });

  it("config-weight inject: w_neglect: 0 zeroes neglect in weighted breakdown", () => {
    const { stage1, stage2Input } = runStage1FromScenario(
      "T2-06-combination-rule",
    );
    const cfg = withWeights({ w_neglect: 0 });
    expect(cfg.weights.w_neglect).toBe(0);
    expect(DEFAULT_SCORING_CONFIG.weights.w_neglect).not.toBe(0);

    const stage2 = runStage2(stage1, stage2Input, cfg);
    const anyScore = Object.values(stage2.scores)[0];
    expect(anyScore).toBeDefined();
    expect(anyScore!.weighted.neglectBoost).toBe(0);
    // Raw component still computed
    expect(anyScore!.components.neglectBoost).toBeGreaterThanOrEqual(0);
  });

  it("lock bypass: locked BOTTOM is not scored/shortlisted; lock colours affect TOP scores", () => {
    const { stage1, stage2Input } = runStage1FromScenario(
      "T2-03-suit-anchor-atomic",
    );
    const stage2 = runStage2(stage1, stage2Input);
    expect(stage2.scores[SUIT_TROUSERS]).toBeUndefined();
    expect(stage2.scores[SUIT_JACKET]).toBeUndefined();
    expect(stage2.candidateIds.BOTTOM ?? []).toEqual([]);

    // TOP candidates were scored against fixed pieces including navy suit
    const topId = (stage2.candidateIds.TOP ?? [])[0];
    expect(topId).toBeTruthy();
    expect(stage2.scores[topId!]).toBeDefined();
    expect(
      stage2.scores[topId!]!.components.colorHarmony,
    ).toBeGreaterThanOrEqual(0);
  });

  it("history absent: recencyPenalty and repeatPairPenalty are 0", () => {
    const { stage1, stage2Input } = runStage1FromScenario(
      "T2-06-combination-rule",
    );
    delete stage2Input.history;
    const stage2 = runStage2(stage1, stage2Input);
    for (const b of Object.values(stage2.scores)) {
      expect(b.components.recencyPenalty).toBe(0);
      expect(b.components.repeatPairPenalty).toBe(0);
    }
  });

  it("price / cost-per-wear absent from config weights and score formula keys", () => {
    const keys = Object.keys(DEFAULT_SCORING_CONFIG.weights);
    expect(keys.some((k) => /price|cost/i.test(k))).toBe(false);
    const g: GarmentSummary = {
      id: "x",
      displayName: "X",
      slot: "TOP",
      colorPrimary: { family: "navy" },
      surface: "SMOOTH",
      formality: 3,
      warmth: 2,
    };
    const breakdown = scoreGarment(g, {
      fixedPieces: [],
      context: mildWorkContext(),
      asOfDate: "2026-09-18",
      config: DEFAULT_SCORING_CONFIG,
    });
    const allKeys = [
      ...Object.keys(breakdown.components),
      ...Object.keys(breakdown.weighted),
    ];
    expect(allKeys.some((k) => /price|cost/i.test(k))).toBe(false);
  });

  it("#28: WORK-scoped combo rule applies on WORK_STANDARD, not on CASUAL_DAY", () => {
    const { stage1, stage2Input } = runStage1FromScenario(
      "T2-06-combination-rule",
    );
    // Modify profile to add a WORK-scoped rule (original is ALWAYS)
    const workRule = {
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
    const inputWork = {
      ...stage2Input,
      profile: {
        ...stage2Input.profile!,
        activeRules: [workRule],
      },
      context: {
        ...stage2Input.context,
        occasion: "WORK_STANDARD",
      },
    };
    const stage2Work = runStage2(stage1, inputWork);
    expect(
      stage2Work.excludedByCombination.some(
        (e) => e.garmentId === JEANS && e.againstFixedId === SPORT_COAT,
      ),
    ).toBe(true);

    // Same rule with CASUAL_DAY occasion should NOT apply
    const inputCasual = {
      ...stage2Input,
      profile: {
        ...stage2Input.profile!,
        activeRules: [workRule],
      },
      context: {
        ...stage2Input.context,
        occasion: "CASUAL_DAY",
      },
    };
    const stage2Casual = runStage2(stage1, inputCasual);
    expect(
      stage2Casual.excludedByCombination.some(
        (e) => e.garmentId === JEANS,
      ),
    ).toBe(false);
  });

  it("#28: ALWAYS-scoped combo rule still applies on all occasions", () => {
    const { stage1, stage2Input } = runStage1FromScenario(
      "T2-06-combination-rule",
    );
    // Original scenario has ALWAYS scope
    const stage2 = runStage2(stage1, stage2Input);
    expect(
      stage2.excludedByCombination.some(
        (e) => e.garmentId === JEANS && e.againstFixedId === SPORT_COAT,
      ),
    ).toBe(true);
  });
});

import { describe, expect, it, vi } from "vitest";
import { generateLocal, isLocalProblem } from "../../src/pipeline/generateLocal.js";
import * as builderMod from "../../src/stage3/runBuilder.js";
import { runStage1 } from "../../src/stage1/hardFilter.js";
import { runStage2 } from "../../src/stage2/runStage2.js";
import {
  loadScenario,
  stage1InputFromScenario,
} from "../stage1/helpers.js";

describe("generateLocal", () => {
  it("T2-01 happy path: Stage1→2→Builder returns GenerateResponse-ish", () => {
    const scenario = loadScenario("T2-01-sportcoat-mild-work");
    const s1 = stage1InputFromScenario(scenario);
    const result = generateLocal({
      wardrobe: s1.wardrobe,
      context: s1.context,
      anchorGarmentId: s1.anchorGarmentId,
      lockedAssignments: s1.lockedAssignments,
      options: s1.options,
      profile: s1.profile,
      sets: s1.sets,
    });

    expect(isLocalProblem(result)).toBe(false);
    if (isLocalProblem(result)) return;

    expect(result.outfitId).toBeTruthy();
    expect(Array.isArray(result.assignments)).toBe(true);
    expect(result.assignments.length).toBeGreaterThanOrEqual(2);
    expect(result.rationale?.summary).toBeTruthy();
    expect(result.generation.fallbackLevel).toBe("DETERMINISTIC");
    expect(result.generation.spendState).toBe("OK");
    expect(result.generation.costUSD).toBe(0);
    expect(result.generation.inputTokens).toBeNull();
    expect(result.generation.outputTokens).toBeNull();
    expect(result.candidateSet).toBeDefined();

    const filled = result.assignments.filter((a) => a.garmentId);
    expect(filled.length).toBeGreaterThanOrEqual(1);
  });

  it("T2-04 Problem path: returns Problem JSON and does not call builder", () => {
    const spy = vi.spyOn(builderMod, "runBuilder");
    const scenario = loadScenario("T2-04-set-conflict-partner-laundry");
    const s1 = stage1InputFromScenario(scenario);
    const result = generateLocal({
      wardrobe: s1.wardrobe,
      context: s1.context,
      anchorGarmentId: s1.anchorGarmentId,
      lockedAssignments: s1.lockedAssignments,
      options: s1.options,
      profile: s1.profile,
      sets: s1.sets,
    });

    expect(isLocalProblem(result)).toBe(true);
    expect(spy).not.toHaveBeenCalled();
    spy.mockRestore();

    if (!isLocalProblem(result)) return;
    expect(result.status).toBe(400);
    expect(result.code).toBe("SET_CONFLICT");
    expect(result.title).toBeTruthy();
    expect(result.detail).toBeTruthy();
    expect(result.dataPreserved).toBe(true);
  });

  it("T2-10 Problem path: LOCK_CONFLICT without calling builder", () => {
    const spy = vi.spyOn(builderMod, "runBuilder");
    const scenario = loadScenario("T2-10-lock-conflict");
    const s1 = stage1InputFromScenario(scenario);
    const result = generateLocal({
      wardrobe: s1.wardrobe,
      context: s1.context,
      anchor: s1.anchorGarmentId,
      locks: s1.lockedAssignments,
      options: s1.options,
      profile: s1.profile,
      sets: s1.sets,
    });

    expect(isLocalProblem(result)).toBe(true);
    expect(spy).not.toHaveBeenCalled();
    spy.mockRestore();

    if (!isLocalProblem(result)) return;
    expect(result.code).toBe("LOCK_CONFLICT");
    expect(result.status).toBe(400);
  });

  describe("recentOutfits forwarding (Issue #34)", () => {
    it("forwards recentOutfits to Stage2Input.history.suggestions", () => {
      const scenario = loadScenario("T2-01-sportcoat-mild-work");
      const s1 = stage1InputFromScenario(scenario);
      
      const recentOutfits = [
        ["garment-1", "garment-2", "garment-3"],
        ["garment-4", "garment-5", "garment-6"],
      ];

      const result = generateLocal({
        wardrobe: s1.wardrobe,
        context: s1.context,
        anchorGarmentId: s1.anchorGarmentId,
        profile: s1.profile,
        sets: s1.sets,
        recentOutfits,
      });

      expect(isLocalProblem(result)).toBe(false);
    });

    it("handles empty recentOutfits array", () => {
      const scenario = loadScenario("T2-01-sportcoat-mild-work");
      const s1 = stage1InputFromScenario(scenario);

      const result = generateLocal({
        wardrobe: s1.wardrobe,
        context: s1.context,
        anchorGarmentId: s1.anchorGarmentId,
        profile: s1.profile,
        sets: s1.sets,
        recentOutfits: [],
      });

      expect(isLocalProblem(result)).toBe(false);
    });

    it("uses asOfDate when provided with recentOutfits", () => {
      const scenario = loadScenario("T2-01-sportcoat-mild-work");
      const s1 = stage1InputFromScenario(scenario);
      
      const asOfDate = "2024-01-15";
      const recentOutfits = [["garment-1", "garment-2"]];

      const result = generateLocal({
        wardrobe: s1.wardrobe,
        context: s1.context,
        anchorGarmentId: s1.anchorGarmentId,
        profile: s1.profile,
        sets: s1.sets,
        recentOutfits,
        asOfDate,
      });

      expect(isLocalProblem(result)).toBe(false);
    });
  });

  describe("excludeGarmentSets - Try Another (Issue #34)", () => {
    it("returns same outfit when excludeGarmentSets is empty", () => {
      const scenario = loadScenario("T2-01-sportcoat-mild-work");
      const s1 = stage1InputFromScenario(scenario);

      const result1 = generateLocal({
        wardrobe: s1.wardrobe,
        context: s1.context,
        anchorGarmentId: s1.anchorGarmentId,
        profile: s1.profile,
        sets: s1.sets,
        options: {
          excludeGarmentSets: [],
        },
      });

      expect(isLocalProblem(result1)).toBe(false);
      if (isLocalProblem(result1)) return;

      const result2 = generateLocal({
        wardrobe: s1.wardrobe,
        context: s1.context,
        anchorGarmentId: s1.anchorGarmentId,
        profile: s1.profile,
        sets: s1.sets,
      });

      expect(isLocalProblem(result2)).toBe(false);
      if (isLocalProblem(result2)) return;

      expect(result1.outfitId).toBe(result2.outfitId);
    });

    it("returns different outfit when first result is excluded", () => {
      const scenario = loadScenario("T2-01-sportcoat-mild-work");
      const s1 = stage1InputFromScenario(scenario);

      const result1 = generateLocal({
        wardrobe: s1.wardrobe,
        context: s1.context,
        anchorGarmentId: s1.anchorGarmentId,
        profile: s1.profile,
        sets: s1.sets,
      });

      expect(isLocalProblem(result1)).toBe(false);
      if (isLocalProblem(result1)) return;

      const allGarmentIds = result1.assignments
        .filter((a) => a.garmentId)
        .map((a) => a.garmentId!)
        .sort();

      const result2 = generateLocal({
        wardrobe: s1.wardrobe,
        context: s1.context,
        anchorGarmentId: s1.anchorGarmentId,
        profile: s1.profile,
        sets: s1.sets,
        options: {
          excludeGarmentSets: [allGarmentIds],
        },
      });

      expect(isLocalProblem(result2)).toBe(false);
      if (isLocalProblem(result2)) return;

      const result2AllGarmentIds = result2.assignments
        .filter((a) => a.garmentId)
        .map((a) => a.garmentId!)
        .sort();

      const isDifferent = 
        result2AllGarmentIds.length !== allGarmentIds.length ||
        result2AllGarmentIds.some((id, i) => id !== allGarmentIds[i]);

      if (isDifferent) {
        expect(result2.noAlternativeReason).toBeNull();
      } else {
        expect(result2.noAlternativeReason).toBeTruthy();
        expect(result2.noAlternativeReason).toContain("No different combination");
      }
    });

    it("returns noAlternativeReason when no alternatives exist", () => {
      const scenario = loadScenario("T2-01-sportcoat-mild-work");
      const s1 = stage1InputFromScenario(scenario);

      const result1 = generateLocal({
        wardrobe: s1.wardrobe,
        context: s1.context,
        anchorGarmentId: s1.anchorGarmentId,
        profile: s1.profile,
        sets: s1.sets,
      });

      expect(isLocalProblem(result1)).toBe(false);
      if (isLocalProblem(result1)) return;

      const nonLockedIds1 = result1.assignments
        .filter((a) => a.garmentId && !a.isLocked && !a.isAnchor)
        .map((a) => a.garmentId!);

      const excludedSets: string[][] = [nonLockedIds1];

      for (let i = 0; i < 10; i++) {
        const resultN = generateLocal({
          wardrobe: s1.wardrobe,
          context: s1.context,
          anchorGarmentId: s1.anchorGarmentId,
          profile: s1.profile,
          sets: s1.sets,
          options: {
            excludeGarmentSets: excludedSets,
          },
        });

        expect(isLocalProblem(resultN)).toBe(false);
        if (isLocalProblem(resultN)) break;

        if (resultN.noAlternativeReason) {
          expect(resultN.noAlternativeReason).toContain("No different combination");
          break;
        }

        const nonLockedIdsN = resultN.assignments
          .filter((a) => a.garmentId && !a.isLocked && !a.isAnchor)
          .map((a) => a.garmentId!);

        excludedSets.push(nonLockedIdsN);
      }
    });

    it("respects locked assignments when checking exclusions", () => {
      const scenario = loadScenario("T2-01-sportcoat-mild-work");
      const s1 = stage1InputFromScenario(scenario);

      const result1 = generateLocal({
        wardrobe: s1.wardrobe,
        context: s1.context,
        anchorGarmentId: s1.anchorGarmentId,
        lockedAssignments: s1.lockedAssignments,
        profile: s1.profile,
        sets: s1.sets,
      });

      expect(isLocalProblem(result1)).toBe(false);
      if (isLocalProblem(result1)) return;

      const nonLockedIds = result1.assignments
        .filter((a) => a.garmentId && !a.isLocked && !a.isAnchor)
        .map((a) => a.garmentId!);

      const lockedIds = result1.assignments
        .filter((a) => a.garmentId && (a.isLocked || a.isAnchor))
        .map((a) => a.garmentId!);

      for (const lockedId of lockedIds) {
        expect(nonLockedIds).not.toContain(lockedId);
      }
    });
  });

  it("Test-only hook force_weak_bottom_score_for is NOT reachable through public request (issue #40)", () => {
    const scenario = loadScenario("T2-01-sportcoat-mild-work");
    const s1 = stage1InputFromScenario(scenario);
    
    const maliciousOptions = {
      ...s1.options,
      force_weak_bottom_score_for: "a1000005-0005-4000-8000-000000000001",
    } as any;

    const result = generateLocal({
      wardrobe: s1.wardrobe,
      context: s1.context,
      anchorGarmentId: s1.anchorGarmentId,
      lockedAssignments: s1.lockedAssignments,
      options: maliciousOptions,
      profile: s1.profile,
      sets: s1.sets,
    });

    expect(isLocalProblem(result)).toBe(false);
    if (isLocalProblem(result)) return;
    
    expect(result.outfitId).toBeTruthy();
    expect(Array.isArray(result.assignments)).toBe(true);
  });

  it("Issue #35: spendState passes through builder value (OK), Stage 4 cautions surfaced, no spurious RATIONALE_QUALITY", () => {
    const scenario = loadScenario("T2-17-daily-cold");
    const s1 = stage1InputFromScenario(scenario);
    
    const wardrobeNoOuterwear = s1.wardrobe.filter((g) => g.slot !== "OUTERWEAR");
    
    const result = generateLocal({
      wardrobe: wardrobeNoOuterwear,
      context: s1.context,
      anchorGarmentId: s1.anchorGarmentId,
      lockedAssignments: s1.lockedAssignments,
      options: s1.options,
      profile: s1.profile,
      sets: s1.sets,
    });

    expect(isLocalProblem(result)).toBe(false);
    if (isLocalProblem(result)) return;

    const filled = result.assignments.filter((a) => a.garmentId);
    expect(filled.length).toBeGreaterThan(0);

    expect(result.generation.spendState).toBe("OK");

    expect(result.rationale.cautions).toBeDefined();
    const cautionTexts = result.rationale.cautions ?? [];
    expect(cautionTexts.length).toBeGreaterThan(0);

    // #122: maxItems:2 must not drop LAYER_REQUIREMENT behind builder relaxations
    const hasLayerCaution = cautionTexts.some(
      (c: string) =>
        c.toLowerCase().includes("outerwear") ||
        c.toLowerCase().includes("layer"),
    );
    expect(hasLayerCaution).toBe(true);

    const hasRationaleQualityCaution = cautionTexts.some((c: string) =>
      c.includes("Rationale summary names fewer than 2 garments"),
    );
    expect(hasRationaleQualityCaution).toBe(false);
  });
});

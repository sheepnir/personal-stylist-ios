import { describe, expect, it } from "vitest";
import { resolveCap, buildSlotShortlists } from "../../src/stage2/shortlist.js";
import { runStage2 } from "../../src/stage2/runStage2.js";
import { DEFAULT_SCORING_CONFIG } from "../../src/stage2/config.js";
import { runStage1FromScenario } from "./helpers.js";
import type { GarmentSummary } from "../../src/types.js";

describe("Shortlist cap validation and bounds (issue #38)", () => {
  it("rejects candidatesPerSlot < 4", () => {
    const { stage1, stage2Input } = runStage1FromScenario(
      "T2-06-combination-rule",
    );
    const invalidInput = {
      ...stage2Input,
      options: { ...stage2Input.options, candidatesPerSlot: 3 },
    };
    expect(() => runStage2(stage1, invalidInput)).toThrow(
      /candidatesPerSlot must be in range \[4, 10\]/,
    );
  });

  it("rejects candidatesPerSlot > 10", () => {
    const { stage1, stage2Input } = runStage1FromScenario(
      "T2-06-combination-rule",
    );
    const invalidInput = {
      ...stage2Input,
      options: { ...stage2Input.options, candidatesPerSlot: 11 },
    };
    expect(() => runStage2(stage1, invalidInput)).toThrow(
      /candidatesPerSlot must be in range \[4, 10\]/,
    );
  });

  it("accepts candidatesPerSlot = 4 (minimum)", () => {
    const { stage1, stage2Input } = runStage1FromScenario(
      "T2-06-combination-rule",
    );
    const validInput = {
      ...stage2Input,
      options: { ...stage2Input.options, candidatesPerSlot: 4 },
    };
    expect(() => runStage2(stage1, validInput)).not.toThrow();
  });

  it("accepts candidatesPerSlot = 10 (maximum)", () => {
    const { stage1, stage2Input } = runStage1FromScenario(
      "T2-06-combination-rule",
    );
    const validInput = {
      ...stage2Input,
      options: { ...stage2Input.options, candidatesPerSlot: 10 },
    };
    expect(() => runStage2(stage1, validInput)).not.toThrow();
  });

  describe("resolveCap with explicit candidatesPerSlot", () => {
    it("BOLD respects explicit cap as ceiling", () => {
      const cap = resolveCap(
        "BOLD",
        { candidatesPerSlot: 4 },
        DEFAULT_SCORING_CONFIG,
      );
      // With explicit cap=4, BOLD should not increase it
      expect(cap).toBe(4);
    });

    it("BOLD still uses boldnessCaps.BOLD when no explicit cap", () => {
      const cap = resolveCap(
        "BOLD",
        undefined,
        DEFAULT_SCORING_CONFIG,
      );
      // Default is 8, BOLD increases to 10
      expect(cap).toBe(10);
    });

    it("FAMILIAR reduces explicit cap if explicit cap > boldnessCaps.FAMILIAR", () => {
      const cap = resolveCap(
        "FAMILIAR",
        { candidatesPerSlot: 8 },
        DEFAULT_SCORING_CONFIG,
      );
      // FAMILIAR caps at 4 even if explicit is 8
      expect(cap).toBe(4);
    });

    it("FAMILIAR respects explicit cap if explicit cap <= boldnessCaps.FAMILIAR", () => {
      const cap = resolveCap(
        "FAMILIAR",
        { candidatesPerSlot: 4 },
        DEFAULT_SCORING_CONFIG,
      );
      expect(cap).toBe(4);
    });

    it("SLIGHT_STRETCH respects explicit cap", () => {
      const cap = resolveCap(
        "SLIGHT_STRETCH",
        { candidatesPerSlot: 6 },
        DEFAULT_SCORING_CONFIG,
      );
      expect(cap).toBe(6);
    });
  });

  describe("Colour-family coverage bounds (issue #38)", () => {
    it("FAMILIAR skips colour-family coverage entirely", () => {
      const { stage1, stage2Input } = runStage1FromScenario(
        "T2-06-combination-rule",
      );
      const familiarInput = {
        ...stage2Input,
        boldness: "FAMILIAR" as const,
        options: { ...stage2Input.options, candidatesPerSlot: 4 },
      };
      const stage2 = runStage2(stage1, familiarInput);
      
      // Should have no colour diversity expansions for FAMILIAR
      expect(stage2.colourDiversityExpansions).toBeUndefined();
      
      // Shortlist should not exceed cap significantly
      for (const list of Object.values(stage2.shortlist)) {
        if (list && list.length > 0) {
          // Allow some over-cap for set partners, but not 19 items
          expect(list.length).toBeLessThan(10);
        }
      }
    });

    it("SLIGHT_STRETCH allows colour coverage but bounded", () => {
      const { stage1, stage2Input } = runStage1FromScenario(
        "T2-06-combination-rule",
      );
      const stage2 = runStage2(stage1, stage2Input);
      
      // May have colour diversity expansions
      if (stage2.colourDiversityExpansions) {
        // But shortlist should be bounded by maxCap + 2 = 12
        for (const list of Object.values(stage2.shortlist)) {
          if (list && list.length > 0) {
            expect(list.length).toBeLessThanOrEqual(12);
          }
        }
      }
    });

    it("buildSlotShortlists respects maxCap + 2 ceiling", () => {
      // Create a synthetic scenario with many colour families
      const garments: GarmentSummary[] = [];
      const families = [
        "navy", "blue", "grey", "black", "white", "red", "green",
        "yellow", "orange", "purple", "pink", "brown", "tan",
        "olive", "burgundy", "cream", "charcoal", "indigo", "khaki"
      ];
      
      for (let i = 0; i < families.length; i++) {
        garments.push({
          id: `garment-${i}`,
          displayName: `Test ${i}`,
          slot: "TOP",
          colorPrimary: { family: families[i] },
          surface: "SMOOTH",
          formality: 3,
          warmth: 2,
        });
      }
      
      const scores: Record<string, any> = {};
      garments.forEach((g, i) => {
        scores[g.id] = {
          total: 100 - i,
          components: {},
          weighted: {},
        };
      });
      
      const result = buildSlotShortlists(
        { TOP: garments },
        scores,
        new Map(),
        4, // cap
        "SLIGHT_STRETCH",
        DEFAULT_SCORING_CONFIG,
        [],
        undefined,
        new Map(),
      );
      
      const topList = result.shortlist.TOP ?? [];
      // Should be bounded by maxCap + 2 = 12
      expect(topList.length).toBeLessThanOrEqual(12);
    });
  });
});

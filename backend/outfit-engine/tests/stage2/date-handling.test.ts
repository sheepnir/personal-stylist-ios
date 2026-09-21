import { describe, expect, it } from "vitest";
import { neglectBoost } from "../../src/stage2/components/neglectBoost.js";
import { recencyPenalty } from "../../src/stage2/components/recencyPenalty.js";
import { repeatPairPenalty } from "../../src/stage2/components/repeatPairPenalty.js";
import { DEFAULT_SCORING_CONFIG } from "../../src/stage2/config.js";
import type { GarmentSummary, Stage2History } from "../../src/types.js";

const mockGarment = (overrides: Partial<GarmentSummary> = {}): GarmentSummary => ({
  id: "test-garment-1",
  displayName: "Test Garment",
  slot: "TOP",
  colorPrimary: { family: "BLACK", hex: "#000000" },
  ...overrides,
});

describe("Scoring components handle invalid dates (fix #39)", () => {
  describe("neglectBoost", () => {
    it("returns valid score for valid lastWornOn", () => {
      const g = mockGarment({ lastWornOn: "2026-09-15" });
      const score = neglectBoost(g, "2026-09-19", DEFAULT_SCORING_CONFIG);
      expect(score).toBeGreaterThan(0);
      expect(Number.isNaN(score)).toBe(false);
      expect(Number.isFinite(score)).toBe(true);
    });

    it("handles invalid lastWornOn gracefully, falls back to daysSinceIntake", () => {
      const g = mockGarment({ 
        lastWornOn: "yesterday", // invalid
        daysSinceIntake: 10 
      });
      const score = neglectBoost(g, "2026-09-19", DEFAULT_SCORING_CONFIG);
      expect(Number.isNaN(score)).toBe(false);
      expect(Number.isFinite(score)).toBe(true);
      expect(score).toBeGreaterThan(0);
    });

    it("handles both invalid dates gracefully, returns default 0.5", () => {
      const g = mockGarment({ 
        lastWornOn: "invalid-date",
        daysSinceIntake: undefined
      });
      const score = neglectBoost(g, "2026-09-19", DEFAULT_SCORING_CONFIG);
      expect(score).toBe(0.5);
      expect(Number.isNaN(score)).toBe(false);
    });

    it("handles invalid asOfDate gracefully", () => {
      const g = mockGarment({ lastWornOn: "2026-09-15" });
      const score = neglectBoost(g, "not-a-date", DEFAULT_SCORING_CONFIG);
      expect(Number.isNaN(score)).toBe(false);
      expect(score).toBe(0.5); // Falls back to default
    });

    it("correctly handles calendar dates without UTC conversion", () => {
      const g = mockGarment({ lastWornOn: "2026-09-19" });
      // Same day in California evening
      const score = neglectBoost(g, "2026-09-19T23:30:00-07:00", DEFAULT_SCORING_CONFIG);
      expect(Number.isNaN(score)).toBe(false);
      // Should be 0 days (worn today), not 1 day (worn yesterday)
      expect(score).toBeLessThan(0.01); // Close to 0 for same day
    });
  });

  describe("recencyPenalty", () => {
    it("returns valid penalty for valid date", () => {
      const g = mockGarment({ lastWornOn: "2026-09-18" });
      const penalty = recencyPenalty(g, "2026-09-19", null, DEFAULT_SCORING_CONFIG);
      expect(Number.isNaN(penalty)).toBe(false);
      expect(Number.isFinite(penalty)).toBe(true);
      expect(penalty).toBeGreaterThan(0);
    });

    it("handles invalid lastWornOn gracefully, returns 0", () => {
      const g = mockGarment({ lastWornOn: "yesterday" });
      const penalty = recencyPenalty(g, "2026-09-19", null, DEFAULT_SCORING_CONFIG);
      expect(penalty).toBe(0);
      expect(Number.isNaN(penalty)).toBe(false);
    });

    it("handles invalid asOfDate gracefully, returns 0", () => {
      const g = mockGarment({ lastWornOn: "2026-09-15" });
      const penalty = recencyPenalty(g, "invalid", null, DEFAULT_SCORING_CONFIG);
      expect(penalty).toBe(0);
      expect(Number.isNaN(penalty)).toBe(false);
    });

    it("handles invalid dates in history gracefully", () => {
      const g = mockGarment();
      const history: Stage2History = {
        wears: [
          { garmentId: "test-garment-1", wornOn: "yesterday" }, // invalid
        ],
      };
      const penalty = recencyPenalty(g, "2026-09-19", history, DEFAULT_SCORING_CONFIG);
      expect(penalty).toBe(0);
      expect(Number.isNaN(penalty)).toBe(false);
    });

    it("correctly handles calendar dates without UTC conversion", () => {
      const g = mockGarment({ lastWornOn: "2026-09-19" });
      // Same day in California evening - should have high penalty
      const penalty = recencyPenalty(g, "2026-09-19T23:30:00-07:00", null, DEFAULT_SCORING_CONFIG);
      expect(Number.isNaN(penalty)).toBe(false);
      expect(penalty).toBeGreaterThan(0.9); // Worn today = high penalty
    });
  });

  describe("repeatPairPenalty", () => {
    it("returns valid penalty for valid dates", () => {
      const g = mockGarment();
      const fixed = [mockGarment({ id: "fixed-1" })];
      const history: Stage2History = {
        suggestions: [
          {
            garmentIds: ["test-garment-1", "fixed-1"],
            suggestedAt: "2026-09-15",
          },
        ],
      };
      const penalty = repeatPairPenalty(g, fixed, "2026-09-19", history, DEFAULT_SCORING_CONFIG);
      expect(Number.isNaN(penalty)).toBe(false);
      expect(Number.isFinite(penalty)).toBe(true);
    });

    it("handles invalid suggestedAt dates gracefully, skips those suggestions", () => {
      const g = mockGarment();
      const fixed = [mockGarment({ id: "fixed-1" })];
      const history: Stage2History = {
        suggestions: [
          {
            garmentIds: ["test-garment-1", "fixed-1"],
            suggestedAt: "yesterday", // invalid - should be skipped
          },
          {
            garmentIds: ["test-garment-1", "fixed-1"],
            suggestedAt: "2026-09-15", // valid
          },
        ],
      };
      const penalty = repeatPairPenalty(g, fixed, "2026-09-19", history, DEFAULT_SCORING_CONFIG);
      expect(penalty).toBeGreaterThan(0); // Valid suggestion still counted
      expect(Number.isNaN(penalty)).toBe(false);
    });

    it("handles invalid asOfDate gracefully, returns 0", () => {
      const g = mockGarment();
      const fixed = [mockGarment({ id: "fixed-1" })];
      const history: Stage2History = {
        suggestions: [
          {
            garmentIds: ["test-garment-1", "fixed-1"],
            suggestedAt: "2026-09-15",
          },
        ],
      };
      const penalty = repeatPairPenalty(g, fixed, "not-a-date", history, DEFAULT_SCORING_CONFIG);
      expect(penalty).toBe(0); // All suggestions filtered out due to invalid asOfDate
      expect(Number.isNaN(penalty)).toBe(false);
    });

    it("returns 0 when all dates are invalid", () => {
      const g = mockGarment();
      const fixed = [mockGarment({ id: "fixed-1" })];
      const history: Stage2History = {
        suggestions: [
          {
            garmentIds: ["test-garment-1", "fixed-1"],
            suggestedAt: "invalid",
          },
        ],
      };
      const penalty = repeatPairPenalty(g, fixed, "2026-09-19", history, DEFAULT_SCORING_CONFIG);
      expect(penalty).toBe(0);
      expect(Number.isNaN(penalty)).toBe(false);
    });
  });
});

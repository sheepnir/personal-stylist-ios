/**
 * Regression tests for #30-1: Multiple fixed accessories must all survive
 * (not overwritten by Map<Slot,string> last-write-wins).
 */
import { describe, expect, it } from "vitest";
import { runBuilder } from "../../src/stage3/runBuilder.js";
import { loadGarments } from "../stage1/helpers.js";
import type {
  BuilderInput,
  ScoredCandidate,
  Slot,
  Stage2Result,
} from "../../src/types.js";

const BELT_ID = "a1000007-0007-4000-8000-000000000001";
const WATCH_ID = "a1000007-0007-4000-8000-000000000004";
const TIE_ID = "a1000007-0007-4000-8000-000000000002";

function syntheticStage2(
  fixed: Stage2Result["fixed"],
): Stage2Result {
  return {
    ok: true,
    shortlist: {
      TOP: [],
      BOTTOM: [],
      FOOTWEAR: [],
      ACCESSORY: [],
    },
    candidateIds: {},
    scores: {},
    excludedByCombination: [],
    setShortlistExpansions: [],
    fixed,
    gaps: [],
    relaxationsApplied: [],
    meta: {
      capUsed: 8,
      boldness: "SLIGHT_STRETCH",
      weightsVersion: "1.0.0",
    },
  };
}

describe("#30-1 regression: multi-accessory not overwritten", () => {
  it("three fixed accessories: all survive in outfitIds (not Map overwrite)", () => {
    const allGarments = loadGarments();
    const wardrobe = allGarments.filter((g) => g.readiness !== "DRAFT");
    
    const stage2 = syntheticStage2([
      { garmentId: BELT_ID, slot: "ACCESSORY", role: "lock" },
      { garmentId: WATCH_ID, slot: "ACCESSORY", role: "lock" },
      { garmentId: TIE_ID, slot: "ACCESSORY", role: "anchor" },
    ]);

    const input: BuilderInput = {
      wardrobe,
      context: {
        occasion: "WORK_STANDARD",
        occasionFormality: 3,
        temperatureBand: "MILD",
        precipitation: false,
      },
      options: {},
      sets: [],
    };

    const result = runBuilder(stage2, input);

    // All three accessories should be in assignments
    const accessoryAssignments = result.assignments.filter(
      (a) => a.slot === "ACCESSORY",
    );
    expect(accessoryAssignments).toHaveLength(3);

    const assignedIds = accessoryAssignments.map((a) => a.garmentId);
    expect(assignedIds).toContain(BELT_ID);
    expect(assignedIds).toContain(WATCH_ID);
    expect(assignedIds).toContain(TIE_ID);

    // All should be marked correctly
    const belt = accessoryAssignments.find((a) => a.garmentId === BELT_ID);
    const watch = accessoryAssignments.find((a) => a.garmentId === WATCH_ID);
    const tie = accessoryAssignments.find((a) => a.garmentId === TIE_ID);

    expect(belt?.isLocked).toBe(true);
    expect(watch?.isLocked).toBe(true);
    expect(tie?.isAnchor).toBe(true);
  });

  it("two accessories + free picks: accessories don't compete with themselves", () => {
    const allGarments = loadGarments();
    const wardrobe = allGarments.filter((g) => g.readiness !== "DRAFT");
    
    const stage2 = syntheticStage2([
      { garmentId: BELT_ID, slot: "ACCESSORY", role: "lock" },
      { garmentId: WATCH_ID, slot: "ACCESSORY", role: "anchor" },
    ]);

    const input: BuilderInput = {
      wardrobe,
      context: {
        occasion: "WORK_STANDARD",
        occasionFormality: 3,
        temperatureBand: "MILD",
        precipitation: false,
      },
      options: {},
      sets: [],
    };

    const result = runBuilder(stage2, input);

    // Both accessories should be present
    const accessoryAssignments = result.assignments.filter(
      (a) => a.slot === "ACCESSORY",
    );
    expect(accessoryAssignments.length).toBeGreaterThanOrEqual(2);

    const assignedIds = accessoryAssignments.map((a) => a.garmentId);
    expect(assignedIds).toContain(BELT_ID);
    expect(assignedIds).toContain(WATCH_ID);

    // Check that builderMeta.skipped doesn't include already-used accessories
    const skippedAccessories = result.builderMeta.skipped.filter(
      (s) => s.slot === "ACCESSORY" && s.reason === "ALREADY_USED",
    );
    const skippedIds = skippedAccessories.map((s) => s.garmentId);
    
    // Belt and watch should NOT be in skipped (they're fixed, not competing)
    expect(skippedIds).not.toContain(BELT_ID);
    expect(skippedIds).not.toContain(WATCH_ID);
  });

  it("anchor + lock + free accessory: all three distinct", () => {
    const allGarments = loadGarments();
    const wardrobe = allGarments.filter((g) => g.readiness !== "DRAFT");
    
    const SCARF_ID = "a1000007-0007-4000-8000-000000000003";
    
    const stage2: Stage2Result = {
      ok: true,
      shortlist: {
        TOP: [],
        BOTTOM: [],
        FOOTWEAR: [],
        ACCESSORY: [
          {
            garmentId: SCARF_ID,
            slot: "ACCESSORY",
            score: 10,
            breakdown: { components: {}, weighted: {}, total: 10 },
          },
        ],
      },
      candidateIds: {
        ACCESSORY: [SCARF_ID],
      },
      scores: {},
      excludedByCombination: [],
      setShortlistExpansions: [],
      fixed: [
        { garmentId: BELT_ID, slot: "ACCESSORY", role: "anchor" },
        { garmentId: WATCH_ID, slot: "ACCESSORY", role: "lock" },
      ],
      gaps: [],
      relaxationsApplied: [],
      meta: {
        capUsed: 8,
        boldness: "SLIGHT_STRETCH",
        weightsVersion: "1.0.0",
      },
    };

    const input: BuilderInput = {
      wardrobe,
      context: {
        occasion: "WORK_STANDARD",
        occasionFormality: 3,
        temperatureBand: "MILD",
        precipitation: false,
      },
      options: {},
      sets: [],
    };

    const result = runBuilder(stage2, input, { fillOptionalAccessories: true });

    const accessoryAssignments = result.assignments.filter(
      (a) => a.slot === "ACCESSORY",
    );
    
    // Should have all three: anchor, lock, and free pick
    expect(accessoryAssignments).toHaveLength(3);

    const assignedIds = accessoryAssignments.map((a) => a.garmentId);
    expect(assignedIds).toContain(BELT_ID);
    expect(assignedIds).toContain(WATCH_ID);
    expect(assignedIds).toContain(SCARF_ID);
  });
});

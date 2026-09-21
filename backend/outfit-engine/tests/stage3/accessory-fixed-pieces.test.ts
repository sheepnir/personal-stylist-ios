/**
 * Tests for #30: Anchored/locked accessories — no duplication, distinct categories allowed (D-32).
 */
import { describe, expect, it } from "vitest";
import { generateLocal, isLocalProblem } from "../../src/pipeline/generateLocal.js";
import { runBuilder } from "../../src/stage3/runBuilder.js";
import { runPrechecks } from "../../src/stage1/prechecks.js";
import type {
  BuilderInput,
  GarmentSummary,
  OutfitAssignment,
  Stage1Input,
  Stage2Result,
} from "../../src/types.js";
import { loadGarments } from "../stage1/helpers.js";

const BELT_ID = "a1000007-0007-4000-8000-000000000001";
const TIE_ID = "a1000007-0007-4000-8000-000000000002";
const SCARF_ID = "a1000007-0007-4000-8000-000000000003";
const WATCH_ID = "a1000007-0007-4000-8000-000000000004";
const SPORT_COAT = "a1000003-0003-4000-8000-000000000001";

function syntheticStage2(
  fixed: Stage2Result["fixed"],
  accessoryShortlist: string[] = [],
): Stage2Result {
  return {
    ok: true,
    shortlist: {
      TOP: [],
      BOTTOM: [],
      FOOTWEAR: [],
      ACCESSORY: accessoryShortlist.map((id, i) => ({
        garmentId: id,
        slot: "ACCESSORY",
        score: 10 - i,
        breakdown: { components: {}, weighted: {}, total: 10 - i },
      })),
    },
    candidateIds: {
      ACCESSORY: accessoryShortlist,
    },
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

describe("Fixed accessories (#30)", () => {
  it("belt anchor: appears exactly once in assignments, not duplicated", () => {
    const wardrobe = loadGarments();
    const stage2 = syntheticStage2([
      { garmentId: BELT_ID, slot: "ACCESSORY", role: "anchor" },
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

    const result = runBuilder(stage2, input, { fillOptionalAccessories: false });

    const accessoryAssignments = result.assignments.filter(
      (a) => a.slot === "ACCESSORY",
    );
    const beltAssignments = accessoryAssignments.filter(
      (a) => a.garmentId === BELT_ID,
    );

    expect(beltAssignments).toHaveLength(1);
    expect(beltAssignments[0]?.isAnchor).toBe(true);
    expect(beltAssignments[0]?.garmentId).toBe(BELT_ID);

    // All accessory assignments should be unique by garmentId
    const garmentIds = accessoryAssignments.map((a) => a.garmentId);
    const uniqueIds = [...new Set(garmentIds)];
    expect(garmentIds).toEqual(uniqueIds);
  });

  it("belt lock: appears exactly once, not duplicated", () => {
    const wardrobe = loadGarments();
    const stage2 = syntheticStage2([
      { garmentId: BELT_ID, slot: "ACCESSORY", role: "lock" },
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

    const result = runBuilder(stage2, input, { fillOptionalAccessories: false });

    const beltAssignments = result.assignments.filter(
      (a) => a.slot === "ACCESSORY" && a.garmentId === BELT_ID,
    );

    expect(beltAssignments).toHaveLength(1);
    expect(beltAssignments[0]?.isLocked).toBe(true);
  });

  it("watch anchor + belt lock: both present, distinct categories allowed (D-32)", () => {
    const allGarments = loadGarments();
    const wardrobe = allGarments
      .filter((g) => g.readiness !== "DRAFT")
      .map((g) => 
        // Override watch availability for this test
        g.id === WATCH_ID ? { ...g, availability: "AVAILABLE" as const } : g
      );
    const belt = wardrobe.find((g) => g.id === BELT_ID);
    const watch = wardrobe.find((g) => g.id === WATCH_ID);

    expect(belt?.category).toBe("belt");
    expect(watch?.category).toBe("watch");

    const input: Stage1Input = {
      wardrobe,
      context: {
        occasion: "WORK_STANDARD",
        occasionFormality: 3,
        temperatureBand: "MILD",
        precipitation: false,
      },
      anchorGarmentId: WATCH_ID,
      lockedAssignments: [
        { slot: "ACCESSORY", garmentId: BELT_ID, isLocked: true, isAnchor: false },
      ],
      options: {},
      sets: [],
    };

    const problem = runPrechecks(input);
    expect(problem).toBeNull();
  });

  it("locking anchor itself: allowed (redundant but not error)", () => {
    const allGarments = loadGarments();
    const wardrobe = allGarments.filter((g) => g.readiness !== "DRAFT");
    const input: Stage1Input = {
      wardrobe,
      context: {
        occasion: "WORK_STANDARD",
        occasionFormality: 3,
        temperatureBand: "MILD",
        precipitation: false,
      },
      anchorGarmentId: BELT_ID,
      lockedAssignments: [
        { slot: "ACCESSORY", garmentId: BELT_ID, isLocked: true, isAnchor: false },
      ],
      options: {},
      sets: [],
    };

    const problem = runPrechecks(input);
    expect(problem).toBeNull();
  });

  it("two belt locks of same category: LOCK_CONFLICT", () => {
    // Create two different belt garments with same category
    const wardrobe: GarmentSummary[] = [
      {
        id: "belt-1",
        displayName: "Brown Belt",
        slot: "ACCESSORY",
        category: "belt",
        readiness: "READY",
        availability: "AVAILABLE",
      },
      {
        id: "belt-2",
        displayName: "Black Belt",
        slot: "ACCESSORY",
        category: "belt",
        readiness: "READY",
        availability: "AVAILABLE",
      },
    ];
    
    const input: Stage1Input = {
      wardrobe,
      context: {
        occasion: "WORK_STANDARD",
        occasionFormality: 3,
        temperatureBand: "MILD",
        precipitation: false,
      },
      lockedAssignments: [
        { slot: "ACCESSORY", garmentId: "belt-1", isLocked: true, isAnchor: false },
        { slot: "ACCESSORY", garmentId: "belt-2", isLocked: true, isAnchor: false },
      ],
      options: {},
      sets: [],
    };

    const problem = runPrechecks(input);
    expect(problem).not.toBeNull();
    expect(problem!.code).toBe("LOCK_CONFLICT");
    expect(problem!.detail).toMatch(/belt|same.*category/i);
  });

  it("multiple accessory locks of distinct categories: allowed", () => {
    const allGarments = loadGarments();
    const wardrobe = allGarments
      .filter((g) => g.readiness !== "DRAFT")
      .map((g) => 
        // Override watch availability for this test
        g.id === WATCH_ID ? { ...g, availability: "AVAILABLE" as const } : g
      );
    const belt = wardrobe.find((g) => g.id === BELT_ID);
    const watch = wardrobe.find((g) => g.id === WATCH_ID);
    const tie = wardrobe.find((g) => g.id === TIE_ID);

    expect(belt?.category).toBe("belt");
    expect(watch?.category).toBe("watch");
    expect(tie?.category).toBe("tie");

    const input: Stage1Input = {
      wardrobe,
      context: {
        occasion: "WORK_STANDARD",
        occasionFormality: 3,
        temperatureBand: "MILD",
        precipitation: false,
      },
      lockedAssignments: [
        { slot: "ACCESSORY", garmentId: BELT_ID, isLocked: true, isAnchor: false },
        { slot: "ACCESSORY", garmentId: WATCH_ID, isLocked: true, isAnchor: false },
        { slot: "ACCESSORY", garmentId: TIE_ID, isLocked: true, isAnchor: false },
      ],
      options: {},
      sets: [],
    };

    const problem = runPrechecks(input);
    expect(problem).toBeNull();
  });

  it("two belt locks (same category): LOCK_CONFLICT", () => {
    const wardrobe: GarmentSummary[] = [
      {
        id: "belt-1",
        displayName: "Belt 1",
        slot: "ACCESSORY",
        category: "belt",
        readiness: "READY",
        availability: "AVAILABLE",
      },
      {
        id: "belt-2",
        displayName: "Belt 2",
        slot: "ACCESSORY",
        category: "belt",
        readiness: "READY",
        availability: "AVAILABLE",
      },
    ];

    const input: Stage1Input = {
      wardrobe,
      context: {
        occasion: "WORK_STANDARD",
        occasionFormality: 3,
        temperatureBand: "MILD",
        precipitation: false,
      },
      lockedAssignments: [
        { slot: "ACCESSORY", garmentId: "belt-1", isLocked: true, isAnchor: false },
        { slot: "ACCESSORY", garmentId: "belt-2", isLocked: true, isAnchor: false },
      ],
      options: {},
      sets: [],
    };

    const problem = runPrechecks(input);
    expect(problem).not.toBeNull();
    expect(problem!.code).toBe("LOCK_CONFLICT");
    expect(problem!.detail).toMatch(/belt|same.*category|distinct/i);
    expect(problem!.conflicts).toHaveLength(2);
  });

  it("generateLocal with belt anchor: no VALIDATION_FAILED, no duplicate belt", () => {
    const allGarments = loadGarments();
    const wardrobe = allGarments.filter((g) => g.readiness !== "DRAFT");
    const result = generateLocal({
      wardrobe,
      context: {
        occasion: "WORK_STANDARD",
        occasionFormality: 3,
        temperatureBand: "MILD",
        precipitation: false,
      },
      anchorGarmentId: BELT_ID,
      options: {},
      profile: null,
      sets: [],
    });

    expect(isLocalProblem(result)).toBe(false);
    if (isLocalProblem(result)) return;

    expect(result.assignments).toBeDefined();
    const accessoryAssignments = result.assignments.filter(
      (a) => a.slot === "ACCESSORY",
    );
    const beltCount = accessoryAssignments.filter((a) => a.garmentId === BELT_ID).length;

    expect(beltCount).toBe(1);
  });

  it("TOP anchor + belt lock: distinct slots, no conflict", () => {
    const allGarments = loadGarments();
    const wardrobe = allGarments.filter((g) => g.readiness !== "DRAFT");
    const input: Stage1Input = {
      wardrobe,
      context: {
        occasion: "WORK_STANDARD",
        occasionFormality: 3,
        temperatureBand: "MILD",
        precipitation: false,
      },
      anchorGarmentId: SPORT_COAT,
      lockedAssignments: [
        { slot: "ACCESSORY", garmentId: BELT_ID, isLocked: true, isAnchor: false },
      ],
      options: {},
      sets: [],
    };

    const problem = runPrechecks(input);
    expect(problem).toBeNull();
  });

  it("builder with multiple fixed accessories: all present exactly once", () => {
    const allGarments = loadGarments();
    const wardrobe = allGarments.filter((g) => g.readiness !== "DRAFT");
    const stage2 = syntheticStage2([
      { garmentId: BELT_ID, slot: "ACCESSORY", role: "anchor" },
      { garmentId: WATCH_ID, slot: "ACCESSORY", role: "lock" },
      { garmentId: TIE_ID, slot: "ACCESSORY", role: "lock" },
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

    const result = runBuilder(stage2, input, { fillOptionalAccessories: false });

    const accessoryAssignments = result.assignments.filter(
      (a) => a.slot === "ACCESSORY",
    );

    expect(accessoryAssignments).toHaveLength(3);

    const belt = accessoryAssignments.find((a) => a.garmentId === BELT_ID);
    const watch = accessoryAssignments.find((a) => a.garmentId === WATCH_ID);
    const tie = accessoryAssignments.find((a) => a.garmentId === TIE_ID);

    expect(belt?.isAnchor).toBe(true);
    expect(watch?.isLocked).toBe(true);
    expect(tie?.isLocked).toBe(true);

    // No duplicates
    const garmentIds = accessoryAssignments.map((a) => a.garmentId);
    expect(garmentIds).toEqual([...new Set(garmentIds)]);
  });
});

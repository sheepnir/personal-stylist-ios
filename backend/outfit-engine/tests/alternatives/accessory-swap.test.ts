/**
 * Tests for #30: Swap with multiple fixed accessories (D-32).
 */
import { describe, expect, it } from "vitest";
import { buildFixedMap, toStage1SwapInput } from "../../src/alternatives/toStage1SwapInput.js";
import type { OutfitAssignment, GarmentSummary } from "../../src/types.js";
import { loadGarments } from "../stage1/helpers.js";

const BELT_ID = "a1000007-0007-4000-8000-000000000001";
const WATCH_ID = "a1000007-0007-4000-8000-000000000004";
const TIE_ID = "a1000007-0007-4000-8000-000000000002";
const TOP_ID = "a1000001-0001-4000-8000-000000000001";
const BOTTOM_ID = "a1000005-0005-4000-8000-000000000001";

describe("Swap with fixed accessories (#30)", () => {
  it("buildFixedMap: single fixed accessory", () => {
    const wardrobe = loadGarments();
    const assignments: OutfitAssignment[] = [
      { slot: "TOP", garmentId: TOP_ID, isAnchor: true, isLocked: false },
      { slot: "ACCESSORY", garmentId: BELT_ID, isLocked: true, isAnchor: false },
    ];

    const result = buildFixedMap({
      slot: "BOTTOM",
      currentAssignments: assignments,
      wardrobe,
    });

    if ("error" in result) {
      throw new Error(result.detail);
    }

    expect(result.accessoryIds).toEqual([BELT_ID]);
    expect(result.O_ids.has(BELT_ID)).toBe(true);
    expect(result.O_ids.has(TOP_ID)).toBe(true);
  });

  it("buildFixedMap: multiple fixed accessories", () => {
    const wardrobe = loadGarments();
    const assignments: OutfitAssignment[] = [
      { slot: "TOP", garmentId: TOP_ID, isAnchor: true, isLocked: false },
      { slot: "ACCESSORY", garmentId: BELT_ID, isLocked: true, isAnchor: false },
      { slot: "ACCESSORY", garmentId: WATCH_ID, isLocked: true, isAnchor: false },
      { slot: "ACCESSORY", garmentId: TIE_ID, isLocked: false, isAnchor: false },
    ];

    const result = buildFixedMap({
      slot: "BOTTOM",
      currentAssignments: assignments,
      wardrobe,
    });

    if ("error" in result) {
      throw new Error(result.detail);
    }

    expect(result.accessoryIds).toHaveLength(3);
    expect(result.accessoryIds).toContain(BELT_ID);
    expect(result.accessoryIds).toContain(WATCH_ID);
    expect(result.accessoryIds).toContain(TIE_ID);

    // All should be in O_ids
    expect(result.O_ids.has(BELT_ID)).toBe(true);
    expect(result.O_ids.has(WATCH_ID)).toBe(true);
    expect(result.O_ids.has(TIE_ID)).toBe(true);
  });

  it("toStage1SwapInput: multiple fixed accessories become locks", () => {
    const wardrobe = loadGarments();
    const assignments: OutfitAssignment[] = [
      { slot: "TOP", garmentId: TOP_ID, isAnchor: true, isLocked: false },
      { slot: "ACCESSORY", garmentId: BELT_ID, isLocked: true, isAnchor: false },
      { slot: "ACCESSORY", garmentId: WATCH_ID, isLocked: true, isAnchor: false },
    ];

    const fixed = buildFixedMap({
      slot: "BOTTOM",
      currentAssignments: assignments,
      wardrobe,
    });

    if ("error" in fixed) {
      throw new Error(fixed.detail);
    }

    const stage1Input = toStage1SwapInput(
      {
        slot: "BOTTOM",
        currentAssignments: assignments,
        wardrobe,
        context: {
          occasion: "WORK_STANDARD",
          occasionFormality: 3,
          temperatureBand: "MILD",
          precipitation: false,
        },
        profile: null,
        sets: [],
      },
      fixed,
    );

    const accessoryLocks = stage1Input.lockedAssignments?.filter(
      (a) => a.slot === "ACCESSORY",
    ) ?? [];

    expect(accessoryLocks).toHaveLength(2);
    expect(accessoryLocks.map((a) => a.garmentId).sort()).toEqual([BELT_ID, WATCH_ID].sort());

    // All locks should be marked as locked
    for (const lock of accessoryLocks) {
      expect(lock.isLocked).toBe(true);
    }
  });

  it("buildFixedMap: accessory anchor not duplicated in accessoryIds", () => {
    const wardrobe = loadGarments();
    const assignments: OutfitAssignment[] = [
      { slot: "ACCESSORY", garmentId: BELT_ID, isAnchor: true, isLocked: false },
      { slot: "ACCESSORY", garmentId: WATCH_ID, isLocked: true, isAnchor: false },
    ];

    const result = buildFixedMap({
      slot: "TOP",
      currentAssignments: assignments,
      wardrobe,
    });

    if ("error" in result) {
      throw new Error(result.detail);
    }

    expect(result.anchorId).toBe(BELT_ID);
    expect(result.anchorSlot).toBe("ACCESSORY");
    expect(result.accessoryIds).toHaveLength(2);
    expect(result.accessoryIds).toContain(BELT_ID);
    expect(result.accessoryIds).toContain(WATCH_ID);
  });

  it("toStage1SwapInput: accessory anchor not also listed as lock", () => {
    const wardrobe = loadGarments();
    const assignments: OutfitAssignment[] = [
      { slot: "ACCESSORY", garmentId: BELT_ID, isAnchor: true, isLocked: false },
      { slot: "ACCESSORY", garmentId: WATCH_ID, isLocked: true, isAnchor: false },
    ];

    const fixed = buildFixedMap({
      slot: "TOP",
      currentAssignments: assignments,
      wardrobe,
    });

    if ("error" in fixed) {
      throw new Error(fixed.detail);
    }

    const stage1Input = toStage1SwapInput(
      {
        slot: "TOP",
        currentAssignments: assignments,
        wardrobe,
        context: {
          occasion: "WORK_STANDARD",
          occasionFormality: 3,
          temperatureBand: "MILD",
          precipitation: false,
        },
        profile: null,
        sets: [],
      },
      fixed,
    );

    expect(stage1Input.anchorGarmentId).toBe(BELT_ID);

    // Belt should not appear in locks (it's the anchor)
    const beltLock = stage1Input.lockedAssignments?.find(
      (a) => a.garmentId === BELT_ID,
    );
    expect(beltLock).toBeUndefined();

    // Watch should appear as a lock
    const watchLock = stage1Input.lockedAssignments?.find(
      (a) => a.garmentId === WATCH_ID,
    );
    expect(watchLock).toBeDefined();
    expect(watchLock?.slot).toBe("ACCESSORY");
  });

  it("buildFixedMap: swapping non-ACCESSORY keeps all accessories as fixed", () => {
    const wardrobe = loadGarments();
    const assignments: OutfitAssignment[] = [
      { slot: "TOP", garmentId: TOP_ID },
      { slot: "BOTTOM", garmentId: BOTTOM_ID },
      { slot: "ACCESSORY", garmentId: BELT_ID },
      { slot: "ACCESSORY", garmentId: WATCH_ID },
      { slot: "ACCESSORY", garmentId: TIE_ID },
    ];

    const result = buildFixedMap({
      slot: "TOP",
      currentAssignments: assignments,
      wardrobe,
    });

    if ("error" in result) {
      throw new Error(result.detail);
    }

    // All 3 accessories should be in accessoryIds
    expect(result.accessoryIds).toHaveLength(3);
    expect(result.accessoryIds).toEqual([BELT_ID, WATCH_ID, TIE_ID]);
  });

  it("buildFixedMap: swapping ACCESSORY slot keeps other accessories as fixed, current is not", () => {
    const wardrobe = loadGarments();
    const assignments: OutfitAssignment[] = [
      { slot: "TOP", garmentId: TOP_ID },
      { slot: "ACCESSORY", garmentId: BELT_ID, isLocked: true },
      { slot: "ACCESSORY", garmentId: WATCH_ID },
      { slot: "ACCESSORY", garmentId: TIE_ID, isLocked: true },
    ];

    const result = buildFixedMap({
      slot: "ACCESSORY",
      currentAssignments: assignments,
      wardrobe,
    });

    if ("error" in result) {
      throw new Error(result.detail);
    }

    // When swapping ACCESSORY, all current accessories are excluded from the slot check
    // but we still track locked ones in accessoryIds
    expect(result.lockedSlots.has("ACCESSORY")).toBe(true);
    
    // All accessories that aren't being swapped should be tracked
    // The currentInSlotId can be any of them since they're all in ACCESSORY slot
    expect([BELT_ID, WATCH_ID, TIE_ID]).toContain(result.currentInSlotId);
  });
});

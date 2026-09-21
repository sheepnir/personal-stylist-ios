/**
 * Regression test for #30-2: When swapping ACCESSORY, sibling accessories
 * must NOT reappear as alternatives (they must stay excluded).
 */
import { describe, expect, it } from "vitest";
import { rankAlternatives, isAlternativesProblem } from "../../src/alternatives/rankAlternatives.js";
import { loadGarments } from "../stage1/helpers.js";
import type { OutfitAssignment } from "../../src/types.js";

const BELT_ID = "a1000007-0007-4000-8000-000000000001";
const TIE_ID = "a1000007-0007-4000-8000-000000000002";
const SCARF_ID = "a1000007-0007-4000-8000-000000000003";
const WATCH_ID = "a1000007-0007-4000-8000-000000000004";
const TOP_ID = "a1000001-0001-4000-8000-000000000001";
const BOTTOM_ID = "a1000005-0005-4000-8000-000000000001";

describe("#30-2 regression: ACCESSORY swap excludes siblings", () => {
  it("swap ACCESSORY: current siblings do NOT appear in alternatives", () => {
    const allGarments = loadGarments();
    const wardrobe = allGarments
      .filter((g) => g.readiness !== "DRAFT")
      .map((g) => {
        // Override availability for test garments
        if (g.id === WATCH_ID || g.id === SCARF_ID || g.id === BOTTOM_ID) {
          return { ...g, availability: "AVAILABLE" as const };
        }
        return g;
      });

    // Current outfit: TOP + BOTTOM + belt + watch
    const currentAssignments: OutfitAssignment[] = [
      { slot: "TOP", garmentId: TOP_ID, isAnchor: false, isLocked: false },
      { slot: "BOTTOM", garmentId: BOTTOM_ID, isAnchor: false, isLocked: false },
      { slot: "ACCESSORY", garmentId: BELT_ID, isAnchor: false, isLocked: false },
      { slot: "ACCESSORY", garmentId: WATCH_ID, isAnchor: false, isLocked: false },
    ];

    // Swap one ACCESSORY for another
    const result = rankAlternatives({
      slot: "ACCESSORY",
      currentAssignments,
      wardrobe,
      context: {
        occasion: "WORK_STANDARD",
        occasionFormality: 3,
        temperatureBand: "MILD",
        precipitation: false,
      },
      profile: null,
      sets: [],
      limit: 10,
    });

    expect(isAlternativesProblem(result)).toBe(false);
    if (isAlternativesProblem(result)) return;

    const alternativeIds = result.alternatives.map((a) => a.garmentId);

    // Belt and watch are current siblings - they must NOT appear in alternatives
    expect(alternativeIds).not.toContain(BELT_ID);
    expect(alternativeIds).not.toContain(WATCH_ID);

    // Other accessories (tie, scarf) CAN appear
    // (as long as they have distinct categories from belt+watch)
  });

  it("swap ACCESSORY with anchor: anchor sibling excluded from alternatives", () => {
    const allGarments = loadGarments();
    const wardrobe = allGarments
      .filter((g) => g.readiness !== "DRAFT")
      .map((g) => {
        // Override availability for test garments
        if (g.id === WATCH_ID || g.id === SCARF_ID || g.id === BOTTOM_ID) {
          return { ...g, availability: "AVAILABLE" as const };
        }
        return g;
      });

    // Current outfit: belt as anchor + watch as free accessory
    const currentAssignments: OutfitAssignment[] = [
      { slot: "TOP", garmentId: TOP_ID, isAnchor: false, isLocked: false },
      { slot: "BOTTOM", garmentId: BOTTOM_ID, isAnchor: false, isLocked: false },
      { slot: "ACCESSORY", garmentId: BELT_ID, isAnchor: true, isLocked: false },
      { slot: "ACCESSORY", garmentId: WATCH_ID, isAnchor: false, isLocked: false },
    ];

    const result = rankAlternatives({
      slot: "ACCESSORY",
      currentAssignments,
      wardrobe,
      context: {
        occasion: "WORK_STANDARD",
        occasionFormality: 3,
        temperatureBand: "MILD",
        precipitation: false,
      },
      profile: null,
      sets: [],
      limit: 10,
    });

    expect(isAlternativesProblem(result)).toBe(false);
    if (isAlternativesProblem(result)) return;

    const alternativeIds = result.alternatives.map((a) => a.garmentId);

    // Belt (anchor) and watch (sibling) must NOT appear
    expect(alternativeIds).not.toContain(BELT_ID);
    expect(alternativeIds).not.toContain(WATCH_ID);
  });

  it("swap ACCESSORY with locks: locked siblings excluded", () => {
    const allGarments = loadGarments();
    const wardrobe = allGarments
      .filter((g) => g.readiness !== "DRAFT")
      .map((g) => {
        // Override availability for test garments
        if (g.id === WATCH_ID || g.id === SCARF_ID || g.id === BOTTOM_ID) {
          return { ...g, availability: "AVAILABLE" as const };
        }
        return g;
      });

    // Current outfit: belt locked + watch locked
    const currentAssignments: OutfitAssignment[] = [
      { slot: "TOP", garmentId: TOP_ID, isAnchor: false, isLocked: false },
      { slot: "BOTTOM", garmentId: BOTTOM_ID, isAnchor: false, isLocked: false },
      { slot: "ACCESSORY", garmentId: BELT_ID, isAnchor: false, isLocked: true },
      { slot: "ACCESSORY", garmentId: WATCH_ID, isAnchor: false, isLocked: true },
    ];

    const result = rankAlternatives({
      slot: "ACCESSORY",
      currentAssignments,
      wardrobe,
      context: {
        occasion: "WORK_STANDARD",
        occasionFormality: 3,
        temperatureBand: "MILD",
        precipitation: false,
      },
      profile: null,
      sets: [],
      limit: 10,
    });

    expect(isAlternativesProblem(result)).toBe(false);
    if (isAlternativesProblem(result)) return;

    const alternativeIds = result.alternatives.map((a) => a.garmentId);

    // Both locked accessories must NOT appear
    expect(alternativeIds).not.toContain(BELT_ID);
    expect(alternativeIds).not.toContain(WATCH_ID);
  });

  it("swap ACCESSORY: three current accessories, all excluded from alternatives", () => {
    const allGarments = loadGarments();
    const wardrobe = allGarments
      .filter((g) => g.readiness !== "DRAFT")
      .map((g) => {
        // Override availability for test garments
        if (g.id === WATCH_ID || g.id === SCARF_ID || g.id === BOTTOM_ID) {
          return { ...g, availability: "AVAILABLE" as const };
        }
        return g;
      });

    // Current outfit: belt + watch + tie (3 accessories)
    const currentAssignments: OutfitAssignment[] = [
      { slot: "TOP", garmentId: TOP_ID, isAnchor: false, isLocked: false },
      { slot: "BOTTOM", garmentId: BOTTOM_ID, isAnchor: false, isLocked: false },
      { slot: "ACCESSORY", garmentId: BELT_ID, isAnchor: false, isLocked: false },
      { slot: "ACCESSORY", garmentId: WATCH_ID, isAnchor: false, isLocked: false },
      { slot: "ACCESSORY", garmentId: TIE_ID, isAnchor: false, isLocked: false },
    ];

    const result = rankAlternatives({
      slot: "ACCESSORY",
      currentAssignments,
      wardrobe,
      context: {
        occasion: "WORK_STANDARD",
        occasionFormality: 3,
        temperatureBand: "MILD",
        precipitation: false,
      },
      profile: null,
      sets: [],
      limit: 10,
    });

    expect(isAlternativesProblem(result)).toBe(false);
    if (isAlternativesProblem(result)) return;

    const alternativeIds = result.alternatives.map((a) => a.garmentId);

    // All three current accessories must NOT appear
    expect(alternativeIds).not.toContain(BELT_ID);
    expect(alternativeIds).not.toContain(WATCH_ID);
    expect(alternativeIds).not.toContain(TIE_ID);

    // Only scarf (or no alternatives) should be available
    if (alternativeIds.length > 0) {
      // If there are alternatives, they should only be items not currently worn
      for (const id of alternativeIds) {
        expect([BELT_ID, WATCH_ID, TIE_ID]).not.toContain(id);
      }
    }
  });

  it("swap non-ACCESSORY slot: accessories remain fixed and excluded", () => {
    const allGarments = loadGarments();
    const wardrobe = allGarments
      .filter((g) => g.readiness !== "DRAFT")
      .map((g) => {
        // Override availability for test garments
        if (g.id === WATCH_ID || g.id === SCARF_ID || g.id === BOTTOM_ID) {
          return { ...g, availability: "AVAILABLE" as const };
        }
        return g;
      });

    // Current outfit: TOP + BOTTOM + belt + watch
    const currentAssignments: OutfitAssignment[] = [
      { slot: "TOP", garmentId: TOP_ID, isAnchor: false, isLocked: false },
      { slot: "BOTTOM", garmentId: BOTTOM_ID, isAnchor: false, isLocked: false },
      { slot: "ACCESSORY", garmentId: BELT_ID, isAnchor: false, isLocked: false },
      { slot: "ACCESSORY", garmentId: WATCH_ID, isAnchor: false, isLocked: false },
    ];

    // Swap TOP (not ACCESSORY)
    const result = rankAlternatives({
      slot: "TOP",
      currentAssignments,
      wardrobe,
      context: {
        occasion: "WORK_STANDARD",
        occasionFormality: 3,
        temperatureBand: "MILD",
        precipitation: false,
      },
      profile: null,
      sets: [],
      limit: 10,
    });

    expect(isAlternativesProblem(result)).toBe(false);
    if (isAlternativesProblem(result)) return;

    // Alternatives should be TOPs, not accessories
    const alternativeSlots = result.alternatives.map((a) => {
      const g = wardrobe.find((w) => w.id === a.garmentId);
      return g?.slot;
    });
    
    // All alternatives should be TOP slot items
    for (const slot of alternativeSlots) {
      expect(slot).toBe("TOP");
    }

    // No accessories should appear in alternatives
    const alternativeIds = result.alternatives.map((a) => a.garmentId);
    expect(alternativeIds).not.toContain(BELT_ID);
    expect(alternativeIds).not.toContain(WATCH_ID);
    expect(alternativeIds).not.toContain(TIE_ID);
    expect(alternativeIds).not.toContain(SCARF_ID);
  });
});

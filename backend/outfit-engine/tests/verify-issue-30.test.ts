/**
 * Verification test for issue #30 - the exact scenario from the issue report.
 */
import { describe, expect, it } from "vitest";
import { generateLocal, isLocalProblem } from "../src/pipeline/generateLocal.js";
import { loadGarments } from "./stage1/helpers.js";

describe("Issue #30 verification", () => {
  it("PRD §10.2 scenario #8: Brown Leather Belt anchor succeeds (no VALIDATION_FAILED)", () => {
    const BELT_ID = "a1000007-0007-4000-8000-000000000001";
    const allGarments = loadGarments();
    const wardrobe = allGarments.filter((g) => g.readiness !== "DRAFT");
    
    const belt = wardrobe.find((g) => g.id === BELT_ID);
    expect(belt).toBeDefined();
    expect(belt?.displayName).toBe("Brown Leather Belt");
    expect(belt?.category).toBe("belt");

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

    // Should NOT be a problem
    expect(isLocalProblem(result)).toBe(false);
    if (isLocalProblem(result)) {
      throw new Error(`Unexpected problem: ${result.code} - ${result.detail}`);
    }

    // Belt should appear exactly once in assignments
    const beltAssignments = result.assignments.filter(
      (a) => a.garmentId === BELT_ID,
    );
    expect(beltAssignments).toHaveLength(1);
    expect(beltAssignments[0]?.slot).toBe("ACCESSORY");
    expect(beltAssignments[0]?.isAnchor).toBe(true);

    // Should not have duplicate garment error
    expect(result.assignments).toBeDefined();
    
    // All ACCESSORY assignments should be unique
    const accessoryIds = result.assignments
      .filter((a) => a.slot === "ACCESSORY" && a.garmentId)
      .map((a) => a.garmentId);
    const uniqueAccessoryIds = [...new Set(accessoryIds)];
    expect(accessoryIds).toEqual(uniqueAccessoryIds);
  });

  it("TOP anchor + belt lock: succeeds (different slots)", () => {
    const SPORT_COAT = "a1000003-0003-4000-8000-000000000001";
    const BELT_ID = "a1000007-0007-4000-8000-000000000001";
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
      anchorGarmentId: SPORT_COAT,
      lockedAssignments: [
        { slot: "ACCESSORY", garmentId: BELT_ID, isLocked: true, isAnchor: false },
      ],
      options: {},
      profile: null,
      sets: [],
    });

    expect(isLocalProblem(result)).toBe(false);
    if (isLocalProblem(result)) {
      throw new Error(`Unexpected problem: ${result.code} - ${result.detail}`);
    }

    // Both should be present
    const coatAssignment = result.assignments.find((a) => a.garmentId === SPORT_COAT);
    const beltAssignment = result.assignments.find((a) => a.garmentId === BELT_ID);

    expect(coatAssignment).toBeDefined();
    expect(beltAssignment).toBeDefined();
    expect(coatAssignment?.isAnchor).toBe(true);
    expect(beltAssignment?.isLocked).toBe(true);
  });
});

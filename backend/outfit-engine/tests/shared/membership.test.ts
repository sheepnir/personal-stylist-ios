/**
 * Regression tests for keepTogether membership logic (issue #33).
 */

import { describe, it, expect } from "vitest";
import { buildKeepTogetherMembership } from "../../src/shared/membership.js";
import type { GarmentSummary, GarmentSet } from "../../src/types.js";

function makeGarment(
  partial: Partial<GarmentSummary> &
    Pick<GarmentSummary, "id" | "displayName" | "slot">,
): GarmentSummary {
  return {
    category: "test",
    readiness: "READY",
    availability: "AVAILABLE",
    colorPrimary: { family: "navy" },
    pattern: "SOLID",
    surface: "SMOOTH",
    formality: 3,
    warmth: 2,
    seasons: ["SPRING", "SUMMER", "FALL", "WINTER"],
    setId: null,
    keepTogether: false,
    owned: true,
    ...partial,
  };
}

describe("buildKeepTogetherMembership", () => {
  it("includes all set members when any member has keepTogether: true", () => {
    const wardrobe: GarmentSummary[] = [
      makeGarment({
        id: "jacket-1",
        slot: "JACKET",
        setId: "suit-1",
        keepTogether: true,
        displayName: "Navy Suit Jacket",
      }),
      makeGarment({
        id: "trousers-1",
        slot: "BOTTOM",
        setId: "suit-1",
        keepTogether: false,
        displayName: "Navy Suit Trousers",
      }),
    ];

    const result = buildKeepTogetherMembership(wardrobe, undefined);

    expect(result.has("suit-1")).toBe(true);
    const members = result.get("suit-1")!;
    expect(members).toContain("jacket-1");
    expect(members).toContain("trousers-1");
    expect(members.length).toBe(2);
  });

  it("regression: includes member with keepTogether: false when it precedes keepTogether: true member", () => {
    // Issue #33: If jacket (keepTogether: false) comes before trousers (keepTogether: true),
    // both should be in the set once the trousers establish it.
    const wardrobe: GarmentSummary[] = [
      makeGarment({
        id: "jacket-1",
        slot: "JACKET",
        setId: "suit-1",
        keepTogether: false,
        displayName: "Navy Suit Jacket",
      }),
      makeGarment({
        id: "trousers-1",
        slot: "BOTTOM",
        setId: "suit-1",
        keepTogether: true,
        displayName: "Navy Suit Trousers",
      }),
    ];

    const result = buildKeepTogetherMembership(wardrobe, undefined);

    expect(result.has("suit-1")).toBe(true);
    const members = result.get("suit-1")!;
    expect(members).toContain("jacket-1");
    expect(members).toContain("trousers-1");
    expect(members.length).toBe(2);
  });

  it("regression: includes member with keepTogether: false when it follows keepTogether: true member", () => {
    // The reverse order should also work (this was already working in buildSetMembership)
    const wardrobe: GarmentSummary[] = [
      makeGarment({
        id: "trousers-1",
        slot: "BOTTOM",
        setId: "suit-1",
        keepTogether: true,
        displayName: "Navy Suit Trousers",
      }),
      makeGarment({
        id: "jacket-1",
        slot: "JACKET",
        setId: "suit-1",
        keepTogether: false,
        displayName: "Navy Suit Jacket",
      }),
    ];

    const result = buildKeepTogetherMembership(wardrobe, undefined);

    expect(result.has("suit-1")).toBe(true);
    const members = result.get("suit-1")!;
    expect(members).toContain("jacket-1");
    expect(members).toContain("trousers-1");
    expect(members.length).toBe(2);
  });

  it("uses sets catalog when provided with keepTogether: true", () => {
    const wardrobe: GarmentSummary[] = [
      makeGarment({
        id: "jacket-1",
        slot: "JACKET",
        setId: "suit-1",
        keepTogether: false,
        displayName: "Navy Suit Jacket",
      }),
      makeGarment({
        id: "trousers-1",
        slot: "BOTTOM",
        setId: "suit-1",
        keepTogether: false,
        displayName: "Navy Suit Trousers",
      }),
    ];

    const sets: GarmentSet[] = [
      {
        id: "suit-1",
        keepTogether: true,
        memberGarmentIds: ["jacket-1", "trousers-1"],
      },
    ];

    const result = buildKeepTogetherMembership(wardrobe, sets);

    expect(result.has("suit-1")).toBe(true);
    const members = result.get("suit-1")!;
    expect(members).toContain("jacket-1");
    expect(members).toContain("trousers-1");
    expect(members.length).toBe(2);
  });

  it("ignores sets catalog with keepTogether: false", () => {
    const wardrobe: GarmentSummary[] = [
      makeGarment({
        id: "jacket-1",
        slot: "JACKET",
        setId: "suit-1",
        keepTogether: false,
        displayName: "Navy Suit Jacket",
      }),
      makeGarment({
        id: "trousers-1",
        slot: "BOTTOM",
        setId: "suit-1",
        keepTogether: false,
        displayName: "Navy Suit Trousers",
      }),
    ];

    const sets: GarmentSet[] = [
      {
        id: "suit-1",
        keepTogether: false,
        memberGarmentIds: ["jacket-1", "trousers-1"],
      },
    ];

    const result = buildKeepTogetherMembership(wardrobe, sets);

    expect(result.has("suit-1")).toBe(false);
  });

  it("includes garment with no keepTogether flag when another member has keepTogether: true", () => {
    const wardrobe: GarmentSummary[] = [
      makeGarment({
        id: "jacket-1",
        slot: "JACKET",
        setId: "suit-1",
        displayName: "Navy Suit Jacket",
      }),
      makeGarment({
        id: "trousers-1",
        slot: "BOTTOM",
        setId: "suit-1",
        keepTogether: true,
        displayName: "Navy Suit Trousers",
      }),
    ];

    const result = buildKeepTogetherMembership(wardrobe, undefined);

    expect(result.has("suit-1")).toBe(true);
    const members = result.get("suit-1")!;
    expect(members).toContain("jacket-1");
    expect(members).toContain("trousers-1");
    expect(members.length).toBe(2);
  });

  it("handles three-member set with mixed keepTogether flags", () => {
    const wardrobe: GarmentSummary[] = [
      makeGarment({
        id: "jacket-1",
        slot: "JACKET",
        setId: "suit-1",
        keepTogether: false,
        displayName: "Navy Suit Jacket",
      }),
      makeGarment({
        id: "trousers-1",
        slot: "BOTTOM",
        setId: "suit-1",
        keepTogether: true,
        displayName: "Navy Suit Trousers",
      }),
      makeGarment({
        id: "vest-1",
        slot: "MID_LAYER",
        setId: "suit-1",
        keepTogether: false,
        displayName: "Navy Suit Vest",
      }),
    ];

    const result = buildKeepTogetherMembership(wardrobe, undefined);

    expect(result.has("suit-1")).toBe(true);
    const members = result.get("suit-1")!;
    expect(members).toContain("jacket-1");
    expect(members).toContain("trousers-1");
    expect(members).toContain("vest-1");
    expect(members.length).toBe(3);
  });

  it("returns empty map when no sets have keepTogether: true", () => {
    const wardrobe: GarmentSummary[] = [
      makeGarment({
        id: "jacket-1",
        slot: "JACKET",
        setId: "suit-1",
        keepTogether: false,
        displayName: "Navy Suit Jacket",
      }),
      makeGarment({
        id: "trousers-1",
        slot: "BOTTOM",
        setId: "suit-1",
        keepTogether: false,
        displayName: "Navy Suit Trousers",
      }),
    ];

    const result = buildKeepTogetherMembership(wardrobe, undefined);

    expect(result.size).toBe(0);
  });

  it("handles multiple independent sets", () => {
    const wardrobe: GarmentSummary[] = [
      makeGarment({
        id: "jacket-1",
        slot: "JACKET",
        setId: "suit-1",
        keepTogether: true,
        displayName: "Navy Suit Jacket",
      }),
      makeGarment({
        id: "trousers-1",
        slot: "BOTTOM",
        setId: "suit-1",
        keepTogether: false,
        displayName: "Navy Suit Trousers",
      }),
      makeGarment({
        id: "shirt-1",
        slot: "TOP",
        setId: "formal-set",
        keepTogether: true,
        displayName: "White Dress Shirt",
      }),
      makeGarment({
        id: "tie-1",
        slot: "ACCESSORY",
        setId: "formal-set",
        keepTogether: false,
        displayName: "Navy Tie",
      }),
    ];

    const result = buildKeepTogetherMembership(wardrobe, undefined);

    expect(result.size).toBe(2);
    
    const suit1 = result.get("suit-1")!;
    expect(suit1).toContain("jacket-1");
    expect(suit1).toContain("trousers-1");
    expect(suit1.length).toBe(2);
    
    const formalSet = result.get("formal-set")!;
    expect(formalSet).toContain("shirt-1");
    expect(formalSet).toContain("tie-1");
    expect(formalSet.length).toBe(2);
  });
});

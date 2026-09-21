/**
 * Issue #31: Stage1 lock prechecks gaps
 * Tests for the four specific issues fixed per D-32.
 */
import { describe, expect, it } from "vitest";
import { runPrechecks } from "../../src/stage1/prechecks.js";
import type { Stage1Input, GarmentSummary, OutfitAssignment, GarmentSet } from "../../src/types.js";

const TOP_1 = "top-001";
const TOP_2 = "top-002";
const BOTTOM_1 = "bottom-001";
const JACKET_1 = "jacket-001";
const SUIT_JACKET = "suit-jacket-001";
const SUIT_TROUSERS = "suit-trousers-001";
const ACC_1 = "acc-001";
const ACC_2 = "acc-002";

function makeGarment(
  id: string,
  slot: GarmentSummary["slot"],
  displayName: string,
  overrides?: Partial<GarmentSummary>,
): GarmentSummary {
  return {
    id,
    slot,
    displayName,
    readiness: "READY",
    availability: "AVAILABLE",
    archivedAt: null,
    colorPrimary: { family: "blue" },
    pattern: "SOLID",
    surface: "SMOOTH",
    formality: 2,
    warmth: 2,
    category: "SHIRT",
    ...overrides,
  };
}

function baseInput(overrides?: Partial<Stage1Input>): Stage1Input {
  return {
    wardrobe: [
      makeGarment(TOP_1, "TOP", "Blue Shirt"),
      makeGarment(TOP_2, "TOP", "White Shirt"),
      makeGarment(BOTTOM_1, "BOTTOM", "Jeans"),
      makeGarment(JACKET_1, "JACKET", "Sport Coat"),
      makeGarment(ACC_1, "ACCESSORY", "Watch"),
      makeGarment(ACC_2, "ACCESSORY", "Belt"),
    ],
    context: {
      occasion: "WORK",
      occasionFormality: 3,
      temperatureBand: "MILD",
      precipitation: false,
    },
    profile: { activeRules: [] },
    ...overrides,
  };
}

describe("Issue #31-1: Locking the anchor itself should not LOCK_CONFLICT", () => {
  it("allows redundant anchor lock without conflict", () => {
    const input = baseInput({
      anchorGarmentId: TOP_1,
      lockedAssignments: [
        { slot: "TOP", garmentId: TOP_1 },
      ],
    });

    const problem = runPrechecks(input);
    expect(problem).toBeNull();
  });

  it("still rejects when anchor and a different lock occupy same slot", () => {
    const input = baseInput({
      anchorGarmentId: TOP_1,
      lockedAssignments: [
        { slot: "TOP", garmentId: TOP_2 },
      ],
    });

    const problem = runPrechecks(input);
    expect(problem).not.toBeNull();
    expect(problem!.code).toBe("LOCK_CONFLICT");
    expect(problem!.detail).toMatch(/same slot/i);
    expect(problem!.conflicts).toHaveLength(2);
    expect(problem!.conflicts!.some((c) => c.garmentId === TOP_1)).toBe(true);
    expect(problem!.conflicts!.some((c) => c.garmentId === TOP_2)).toBe(true);
  });
});

describe("Issue #31-2: lock.slot must match garment.slot", () => {
  it("rejects lock when lock.slot does not match garment.slot", () => {
    const input = baseInput({
      lockedAssignments: [
        { slot: "BOTTOM", garmentId: TOP_1 }, // TOP garment locked as BOTTOM
      ],
    });

    const problem = runPrechecks(input);
    expect(problem).not.toBeNull();
    expect(problem!.code).toBe("LOCK_CONFLICT");
    expect(problem!.detail).toMatch(/slot mismatch/i);
    expect(problem!.detail).toMatch(/Blue Shirt/i);
    expect(problem!.conflicts).toHaveLength(1);
    expect(problem!.conflicts![0].garmentId).toBe(TOP_1);
    expect(problem!.conflicts![0].reason).toMatch(/TOP/);
    expect(problem!.conflicts![0].reason).toMatch(/BOTTOM/);
  });

  it("accepts lock when lock.slot matches garment.slot", () => {
    const input = baseInput({
      lockedAssignments: [
        { slot: "TOP", garmentId: TOP_1 },
      ],
    });

    const problem = runPrechecks(input);
    expect(problem).toBeNull();
  });

  it("accepts lock when lock.slot is omitted (defaults to garment.slot)", () => {
    const input = baseInput({
      lockedAssignments: [
        { slot: "TOP", garmentId: TOP_1 },
      ],
    });

    const problem = runPrechecks(input);
    expect(problem).toBeNull();
  });
});

describe("Issue #31-3: Two locks in one non-accessory slot", () => {
  it("rejects two locks in same non-accessory slot (TOP)", () => {
    const input = baseInput({
      lockedAssignments: [
        { slot: "TOP", garmentId: TOP_1 },
        { slot: "TOP", garmentId: TOP_2 },
      ],
    });

    const problem = runPrechecks(input);
    expect(problem).not.toBeNull();
    expect(problem!.code).toBe("LOCK_CONFLICT");
    expect(problem!.detail).toMatch(/Two locks/i);
    expect(problem!.detail).toMatch(/TOP/);
    expect(problem!.conflicts).toHaveLength(2);
    expect(problem!.conflicts!.some((c) => c.garmentId === TOP_1)).toBe(true);
    expect(problem!.conflicts!.some((c) => c.garmentId === TOP_2)).toBe(true);
  });

  it("rejects two locks in same non-accessory slot (BOTTOM)", () => {
    const wardrobe = [
      makeGarment(TOP_1, "TOP", "Blue Shirt"),
      makeGarment(BOTTOM_1, "BOTTOM", "Jeans"),
      makeGarment("bottom-002", "BOTTOM", "Chinos"),
    ];
    const input = baseInput({
      wardrobe,
      lockedAssignments: [
        { slot: "BOTTOM", garmentId: BOTTOM_1 },
        { slot: "BOTTOM", garmentId: "bottom-002" },
      ],
    });

    const problem = runPrechecks(input);
    expect(problem).not.toBeNull();
    expect(problem!.code).toBe("LOCK_CONFLICT");
    expect(problem!.detail).toMatch(/Two locks/i);
    expect(problem!.detail).toMatch(/BOTTOM/);
  });

  it("allows multiple locks in ACCESSORY slot", () => {
    const wardrobe = [
      makeGarment(TOP_1, "TOP", "Blue Shirt"),
      makeGarment(BOTTOM_1, "BOTTOM", "Jeans"),
      makeGarment(ACC_1, "ACCESSORY", "Watch", { category: "watch" }),
      makeGarment(ACC_2, "ACCESSORY", "Belt", { category: "belt" }),
      makeGarment("acc-003", "ACCESSORY", "Sunglasses", { category: "sunglasses" }),
    ];
    const input = baseInput({
      wardrobe,
      lockedAssignments: [
        { slot: "ACCESSORY", garmentId: ACC_1 },
        { slot: "ACCESSORY", garmentId: ACC_2 },
        { slot: "ACCESSORY", garmentId: "acc-003" },
      ],
    });

    const problem = runPrechecks(input);
    expect(problem).toBeNull();
  });

  it("allows locks in different slots", () => {
    const input = baseInput({
      lockedAssignments: [
        { slot: "TOP", garmentId: TOP_1 },
        { slot: "BOTTOM", garmentId: BOTTOM_1 },
        { slot: "JACKET", garmentId: JACKET_1 },
      ],
    });

    const problem = runPrechecks(input);
    expect(problem).toBeNull();
  });
});

describe("Issue #31-4: Set-partner-slot locks validated", () => {
  const suitSet: GarmentSet = {
    id: "suit-set-001",
    memberGarmentIds: [SUIT_JACKET, SUIT_TROUSERS],
    keepTogether: true,
  };

  const GREY_WOOL_TROUSERS = "grey-wool-trousers-001";

  it("rejects lock occupying keepTogether partner's slot with DIFFERENT garment (Code Reviewer repro)", () => {
    // Repro: suit-jacket anchor + Grey Wool Trousers locked in BOTTOM
    // BOTTOM is the slot of suit-trousers (partner of suit-jacket)
    // Should reject because Grey Wool Trousers is NOT the suit partner
    const wardrobe = [
      makeGarment(TOP_1, "TOP", "White Shirt"),
      makeGarment(SUIT_JACKET, "JACKET", "Navy Suit Jacket", {
        setId: suitSet.id,
        keepTogether: true,
      }),
      makeGarment(SUIT_TROUSERS, "BOTTOM", "Navy Suit Trousers", {
        setId: suitSet.id,
        keepTogether: true,
      }),
      makeGarment(GREY_WOOL_TROUSERS, "BOTTOM", "Grey Wool Trousers"),
    ];

    const input = baseInput({
      wardrobe,
      sets: [suitSet],
      anchorGarmentId: SUIT_JACKET,
      lockedAssignments: [
        { slot: "BOTTOM", garmentId: GREY_WOOL_TROUSERS }, // Different garment in partner slot!
      ],
    });

    const problem = runPrechecks(input);
    expect(problem).not.toBeNull();
    expect(problem!.code).toBe("SET_CONFLICT");
    expect(problem!.detail).toMatch(/Grey Wool Trousers/i);
    expect(problem!.detail).toMatch(/Navy Suit/i);
    expect(problem!.detail).toMatch(/keepTogether/i);
    expect(problem!.conflicts).toBeDefined();
    expect(problem!.conflicts!.length).toBeGreaterThanOrEqual(2);
    
    // Should name the suit jacket (anchor/lock), the locked grey trousers, and the partner
    expect(problem!.conflicts!.some((c) => c.garmentId === SUIT_JACKET)).toBe(true);
    expect(problem!.conflicts!.some((c) => c.garmentId === GREY_WOOL_TROUSERS)).toBe(true);
    expect(problem!.conflicts!.some((c) => c.garmentId === SUIT_TROUSERS)).toBe(true);
  });

  it("rejects when non-anchor lock occupies its own partner's slot with different garment", () => {
    const wardrobe = [
      makeGarment(TOP_1, "TOP", "White Shirt"),
      makeGarment(SUIT_JACKET, "JACKET", "Navy Suit Jacket", {
        setId: suitSet.id,
        keepTogether: true,
      }),
      makeGarment(SUIT_TROUSERS, "BOTTOM", "Navy Suit Trousers", {
        setId: suitSet.id,
        keepTogether: true,
      }),
      makeGarment(GREY_WOOL_TROUSERS, "BOTTOM", "Grey Wool Trousers"),
    ];

    const input = baseInput({
      wardrobe,
      sets: [suitSet],
      lockedAssignments: [
        { slot: "JACKET", garmentId: SUIT_JACKET }, // Lock the jacket
        { slot: "BOTTOM", garmentId: GREY_WOOL_TROUSERS }, // Different garment in partner slot
      ],
    });

    const problem = runPrechecks(input);
    expect(problem).not.toBeNull();
    expect(problem!.code).toBe("SET_CONFLICT");
    expect(problem!.detail).toMatch(/Grey Wool Trousers/i);
    expect(problem!.detail).toMatch(/keepTogether/i);
  });

  it("accepts when partner itself is locked (not a different garment)", () => {
    const wardrobe = [
      makeGarment(TOP_1, "TOP", "White Shirt"),
      makeGarment(SUIT_JACKET, "JACKET", "Navy Suit Jacket", {
        setId: suitSet.id,
        keepTogether: true,
      }),
      makeGarment(SUIT_TROUSERS, "BOTTOM", "Navy Suit Trousers", {
        setId: suitSet.id,
        keepTogether: true,
      }),
      makeGarment(GREY_WOOL_TROUSERS, "BOTTOM", "Grey Wool Trousers"),
    ];

    const input = baseInput({
      wardrobe,
      sets: [suitSet],
      anchorGarmentId: SUIT_JACKET,
      lockedAssignments: [
        { slot: "BOTTOM", garmentId: SUIT_TROUSERS }, // Partner itself locked - OK
      ],
    });

    const problem = runPrechecks(input);
    expect(problem).toBeNull();
  });

  it("accepts when lock is in a slot NOT claimed by any partner", () => {
    const wardrobe = [
      makeGarment(TOP_1, "TOP", "White Shirt"),
      makeGarment(SUIT_JACKET, "JACKET", "Navy Suit Jacket", {
        setId: suitSet.id,
        keepTogether: true,
      }),
      makeGarment(SUIT_TROUSERS, "BOTTOM", "Navy Suit Trousers", {
        setId: suitSet.id,
        keepTogether: true,
      }),
      makeGarment(JACKET_1, "JACKET", "Sport Coat"),
    ];

    const input = baseInput({
      wardrobe,
      sets: [suitSet],
      anchorGarmentId: SUIT_JACKET,
      lockedAssignments: [
        { slot: "TOP", garmentId: TOP_1 }, // TOP not claimed by suit partners
      ],
    });

    const problem = runPrechecks(input);
    expect(problem).toBeNull();
  });

  it("rejects when lock has wrong slot for the garment (caught by #31-2)", () => {
    const wardrobe = [
      makeGarment(TOP_1, "TOP", "White Shirt"),
      makeGarment(SUIT_JACKET, "JACKET", "Navy Suit Jacket", {
        setId: suitSet.id,
        keepTogether: true,
      }),
      makeGarment(SUIT_TROUSERS, "BOTTOM", "Navy Suit Trousers", {
        setId: suitSet.id,
        keepTogether: true,
      }),
    ];

    const input = baseInput({
      wardrobe,
      sets: [suitSet],
      anchorGarmentId: SUIT_JACKET,
      lockedAssignments: [
        { slot: "TOP", garmentId: SUIT_TROUSERS }, // Wrong slot for trousers - caught by #31-2
      ],
    });

    const problem = runPrechecks(input);
    expect(problem).not.toBeNull();
    expect(problem!.code).toBe("LOCK_CONFLICT");
    expect(problem!.detail).toMatch(/slot mismatch/i);
  });
});

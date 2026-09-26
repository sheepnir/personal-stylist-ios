import { describe, expect, it } from "vitest";
import { createOwnRecord } from "../../src/provider/safeOwn.js";
import {
  optionKeyIsOffered,
  validateSetTokens,
  validateTokenToGarmentId,
} from "../../src/provider/validateProviderMaps.js";
import { assignmentsGapReasonValid } from "../../src/provider/composeProviderRationale.js";
import { GAP_REASON_MAX_LENGTH } from "../../src/provider/constants.js";

describe("validateProviderMaps", () => {
  it("validateTokenToGarmentId requires non-empty strings", () => {
    expect(validateTokenToGarmentId({ g: "uuid" })).toBe(true);
    expect(validateTokenToGarmentId({ g: 1 })).toBe(false);
  });

  it("optionKeyIsOffered uses ownHas", () => {
    const opts = createOwnRecord<unknown>();
    opts.g_1 = {};
    expect(optionKeyIsOffered(opts, "g_1")).toBe(true);
    expect(optionKeyIsOffered(opts, "toString")).toBe(false);
  });

  it("validateSetTokens checks member shape", () => {
    expect(
      validateSetTokens([
        {
          token: "s_x",
          firstSlot: "JACKET",
          memberGarmentIds: ["a"],
          memberSlots: ["JACKET"],
        },
      ]),
    ).toBe(true);
    expect(
      validateSetTokens([
        {
          token: "bad",
          firstSlot: "JACKET",
          memberGarmentIds: ["a"],
          memberSlots: ["JACKET"],
        },
      ]),
    ).toBe(false);
  });
});

describe("assignmentsGapReasonValid", () => {
  it("rejects gapReason longer than 120 chars", () => {
    const long = "x".repeat(GAP_REASON_MAX_LENGTH + 1);
    expect(
      assignmentsGapReasonValid([
        {
          slot: "FOOTWEAR",
          garmentId: null,
          isAnchor: false,
          isLocked: false,
          gapReason: long,
        },
      ]),
    ).toBe(false);
  });
});

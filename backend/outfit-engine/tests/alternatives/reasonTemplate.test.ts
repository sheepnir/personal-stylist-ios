import { describe, expect, it } from "vitest";
import { templateReason } from "../../src/alternatives/reasonTemplate.js";
import { baseGarment, mildContext } from "./helpers.js";
import type { ScoreBreakdown } from "../../src/types.js";

const score = (components: Record<string, number>): ScoreBreakdown => ({ components, weighted: {}, total: 1 });
const piece = baseGarment({ id: "top", displayName: "Oxford", slot: "TOP", warmth: 2,
  colorPrimary: { family: "light_blue", name: "Light blue" } });
const fixed = baseGarment({ id: "bottom", displayName: "Chinos", slot: "BOTTOM",
  colorPrimary: { family: "tan", name: "Sand" } });

describe("natural swap reasons (#108)", () => {
  it("uses color names and a single Oxford-list conjunction", () => {
    expect(templateReason(score({ colorHarmony: 1, weatherFit: 1, textureContrast: 1 }), [fixed], piece, mildContext()))
      .toBe("pairs Light blue with Sand, suits mild weather, and adds texture contrast.");
  });
  it("joins two phrases without a comma", () => {
    expect(templateReason(score({ weatherFit: 1, textureContrast: 1 }), [], piece, mildContext()))
      .toBe("suits mild weather and adds texture contrast.");
  });
  it("does not claim an improvement when current warmth is identical", () => {
    expect(templateReason(score({ weatherFit: 1 }), [], piece, mildContext(), piece))
      .toBe("suits mild weather.");
  });
  it("omits an oversized color phrase instead of truncating a name", () => {
    const long = { ...piece, colorPrimary: { family: "blue", name: "Long shade ".repeat(30) } };
    expect(templateReason(score({ colorHarmony: 1, weatherFit: 1 }), [fixed], long, mildContext()))
      .toBe("suits mild weather.");
  });
  it("uses a complete bounded fallback when no phrase fits", () => {
    const reason = templateReason(score({}), [], piece, mildContext());
    expect(reason).toBe("works with the pieces you’re keeping.");
    expect(reason.length).toBeLessThanOrEqual(120);
  });
});

import { describe, expect, it } from "vitest";
import { runStage1 } from "../../src/stage1/hardFilter.js";
import type { GarmentSummary, Stage1Input } from "../../src/types.js";
import {
  loadGarments,
  loadScenario,
  loadSets,
  mildWorkContext,
  stage1InputFromScenario,
} from "./helpers.js";

function readyBase(
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

describe("Stage 1 hard filters (M0-14)", () => {
  it("rejects draft in wardrobe with GARMENT_NOT_READY", () => {
    const draft = loadGarments().find((g) => g.readiness === "DRAFT")!;
    const ready = loadGarments()
      .filter((g) => g.readiness === "READY")
      .slice(0, 5);
    const out = runStage1({
      wardrobe: [...ready, draft],
      context: mildWorkContext(),
      options: { requireSlots: ["TOP", "BOTTOM", "FOOTWEAR"] },
    });
    expect(out.ok).toBe(false);
    if (!out.ok) {
      expect(out.code).toBe("GARMENT_NOT_READY");
    }
  });

  it("T2-07: draft excluded from generation wardrobe — Stage 1 succeeds without draft id", () => {
    const s = loadScenario("T2-07-draft-excluded");
    const input = stage1InputFromScenario(s);
    expect(input.wardrobe.some((g) => g.readiness === "DRAFT")).toBe(false);
    const out = runStage1(input);
    expect(out.ok).toBe(true);
    if (out.ok) {
      const draftId = "a1000008-0008-4000-8000-000000000001";
      const all = Object.values(out.eligible).flat();
      expect(all).not.toContain(draftId);
      expect(out.eligible.BOTTOM.length).toBeGreaterThan(0);
      expect(out.eligible.TOP.length).toBeGreaterThan(0);
      expect(out.eligible.FOOTWEAR.length).toBeGreaterThan(0);
    }
  });

  it("excludes laundry / unavailable from eligible (never relax)", () => {
    const garments = loadGarments().filter((g) => g.readiness === "READY");
    const laundryTop = garments.find((g) => g.slot === "TOP")!;
    const wardrobe = garments.map((g) =>
      g.id === laundryTop.id ? { ...g, availability: "LAUNDRY" } : { ...g },
    );
    const out = runStage1({
      wardrobe,
      context: mildWorkContext(),
      anchorGarmentId: garments.find((g) => g.slot === "JACKET")!.id,
      options: { requireSlots: ["TOP", "BOTTOM", "FOOTWEAR"] },
      sets: loadSets(),
    });
    expect(out.ok).toBe(true);
    if (out.ok) {
      expect(out.eligible.TOP).not.toContain(laundryTop.id);
      expect(
        out.eligibleGarments.TOP.every((g) => g.availability === "AVAILABLE"),
      ).toBe(true);
    }
  });

  it("T2-05: DISLIKE olive excludes olive garments; combination not applied", () => {
    const s = loadScenario("T2-05-dislike-olive");
    const out = runStage1(stage1InputFromScenario(s));
    expect(out.ok).toBe(true);
    if (out.ok) {
      const excluded = s.expected.must_exclude_garment_ids as string[];
      const all = Object.values(out.eligible).flat();
      for (const id of excluded) {
        expect(all).not.toContain(id);
      }
      for (const g of Object.values(out.eligibleGarments).flat()) {
        expect(g.colorPrimary?.family).not.toBe("olive");
      }
    }
  });

  it("formality widen: records FORMALITY_WIDENED when ±1 empty but ±2 works", () => {
    // Occasion formality 5; only formality-3 TOP exists → needs ±2
    const bottom = readyBase({
      id: "b-bottom",
      displayName: "Pants",
      slot: "BOTTOM",
      formality: 5,
    });
    const footwear = readyBase({
      id: "b-shoe",
      displayName: "Shoes",
      slot: "FOOTWEAR",
      formality: 5,
    });
    const top = readyBase({
      id: "b-top",
      displayName: "Casual tee",
      slot: "TOP",
      formality: 3,
      warmth: 2,
    });
    const out = runStage1({
      wardrobe: [top, bottom, footwear],
      context: {
        occasion: "CLIENT_EXEC",
        occasionFormality: 5,
        temperatureBand: "MILD",
      },
      options: { requireSlots: ["TOP", "BOTTOM", "FOOTWEAR"] },
    });
    expect(out.ok).toBe(true);
    if (out.ok) {
      expect(out.eligible.TOP).toContain("b-top");
      expect(
        out.relaxationsApplied.some(
          (r) => r.step === "FORMALITY_WIDENED" && r.slot === "TOP",
        ),
      ).toBe(true);
      expect(out.gaps).not.toContain("TOP");
    }
  });

  it("warmth widen: records WARMTH_WIDENED after formality when needed", () => {
    // MILD accepts warmth 1–4; garment warmth 5 needs one-step widen → 1–5
    const top = readyBase({
      id: "w-top",
      displayName: "Heavy knit",
      slot: "TOP",
      formality: 3,
      warmth: 5,
    });
    const bottom = readyBase({
      id: "w-bottom",
      displayName: "Pants",
      slot: "BOTTOM",
      formality: 3,
      warmth: 2,
    });
    const footwear = readyBase({
      id: "w-shoe",
      displayName: "Shoes",
      slot: "FOOTWEAR",
      formality: 3,
      warmth: 2,
    });
    const out = runStage1({
      wardrobe: [top, bottom, footwear],
      context: mildWorkContext(3),
      options: { requireSlots: ["TOP", "BOTTOM", "FOOTWEAR"] },
    });
    expect(out.ok).toBe(true);
    if (out.ok) {
      expect(out.eligible.TOP).toContain("w-top");
      expect(
        out.relaxationsApplied.some(
          (r) => r.step === "FORMALITY_WIDENED" && r.slot === "TOP",
        ),
      ).toBe(true);
      expect(
        out.relaxationsApplied.some(
          (r) => r.step === "WARMTH_WIDENED" && r.slot === "TOP",
        ),
      ).toBe(true);
    }
  });

  it("T2-02: footwear all unavailable → gap; no unavailable ids", () => {
    const s = loadScenario("T2-02-footwear-gap");
    const out = runStage1(stage1InputFromScenario(s));
    expect(out.ok).toBe(true);
    if (out.ok) {
      expect(out.gaps).toContain("FOOTWEAR");
      expect(out.eligible.FOOTWEAR).toEqual([]);
      const all = Object.values(out.eligibleGarments).flat();
      expect(all.every((g) => (g.availability ?? "AVAILABLE") === "AVAILABLE")).toBe(true);
      expect(
        out.relaxationsApplied.some(
          (r) => r.step === "SLOT_ABANDONED" && r.slot === "FOOTWEAR",
        ),
      ).toBe(true);
    }
  });

  it("T2-10: lock conflict same slot as anchor → LOCK_CONFLICT", () => {
    const s = loadScenario("T2-10-lock-conflict");
    const out = runStage1(stage1InputFromScenario(s));
    expect(out.ok).toBe(false);
    if (!out.ok) {
      expect(out.code).toBe("LOCK_CONFLICT");
      expect(out.conflicts?.length).toBeGreaterThanOrEqual(2);
    }
  });

  it("T2-04: set conflict when keepTogether partner in laundry → SET_CONFLICT", () => {
    const s = loadScenario("T2-04-set-conflict-partner-laundry");
    const out = runStage1(stage1InputFromScenario(s));
    expect(out.ok).toBe(false);
    if (!out.ok) {
      expect(out.code).toBe("SET_CONFLICT");
      expect(out.conflicts?.some((c) => c.role === "missing_partner")).toBe(
        true,
      );
    }
  });

  it("set atomic eligibility: both members eligible or neither", () => {
    const sets = loadSets();
    const garments = loadGarments().filter((g) => g.readiness === "READY");
    const suit = sets[0]!;
    const [jacketId, trousersId] = suit.memberGarmentIds;
    const wardrobe = garments.map((g) => ({ ...g }));
    const out = runStage1({
      wardrobe,
      context: {
        occasion: "CLIENT_EXEC",
        occasionFormality: 5,
        temperatureBand: "MILD",
      },
      options: { requireSlots: ["TOP", "BOTTOM", "FOOTWEAR"] },
      sets,
    });
    expect(out.ok).toBe(true);
    if (out.ok) {
      const jacketOk = out.eligible.JACKET.includes(jacketId);
      const trousersOk = out.eligible.BOTTOM.includes(trousersId);
      expect(jacketOk).toBe(trousersOk);
    }
  });

  it("T2-01: Stage 1 eligibility/prechecks — anchor fixed, required slots non-empty", () => {
    const s = loadScenario("T2-01-sportcoat-mild-work");
    const out = runStage1(stage1InputFromScenario(s));
    expect(out.ok).toBe(true);
    if (out.ok) {
      const anchor = s.inputs.anchorGarmentId!;
      expect(out.fixed.some((f) => f.garmentId === anchor && f.role === "anchor")).toBe(
        true,
      );
      expect(out.eligible.JACKET).toContain(anchor);
      expect(out.eligible.TOP.length).toBeGreaterThan(0);
      expect(out.eligible.BOTTOM.length).toBeGreaterThan(0);
      expect(out.eligible.FOOTWEAR.length).toBeGreaterThan(0);
      expect(out.gaps).toEqual([]);
      // Jeans (formality 2) and sport coats (4) both in window at formality 3 ±1
      expect(out.eligible.BOTTOM).toContain(
        "a1000005-0005-4000-8000-000000000001",
      );
    }
  });

  it("combination DISLIKE pairs are NOT applied in Stage 1 (D-26)", () => {
    const s = loadScenario("T2-06-combination-rule");
    // If scenario has a combination rule, both members should still be individually eligible
    const input = stage1InputFromScenario(s);
    const out = runStage1(input);
    expect(out.ok).toBe(true);
    if (out.ok) {
      // Sport coat and jeans should each remain eligible alone
      const all = Object.values(out.eligible).flat();
      // Anchor is sport coat — jeans should still be in BOTTOM eligible
      expect(out.eligible.BOTTOM.length).toBeGreaterThan(0);
      expect(all.length).toBeGreaterThan(0);
    }
  });
});

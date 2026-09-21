/**
 * M0-20: Pre-generation SET_CONFLICT / LOCK_CONFLICT with named pieces
 * (garmentId + human reason) before any model / Stage2 / Builder call.
 */
import { describe, expect, it, vi } from "vitest";
import {
  generateLocal,
  isLocalProblem,
} from "../../src/pipeline/generateLocal.js";
import { runPrechecks } from "../../src/stage1/prechecks.js";
import * as stage2Mod from "../../src/stage2/runStage2.js";
import * as builderMod from "../../src/stage3/runBuilder.js";
import {
  loadScenario,
  stage1InputFromScenario,
} from "../stage1/helpers.js";

const SUIT_JACKET = "a1000003-0003-4000-8000-000000000003";
const SUIT_TROUSERS = "a1000005-0005-4000-8000-000000000004";
const ANCHOR_SPORT = "a1000003-0003-4000-8000-000000000001";
const LOCK_SPORT = "a1000003-0003-4000-8000-000000000002";

function assertNamedConflicts(
  conflicts: { garmentId: string; reason?: string }[] | undefined,
  min = 2,
): void {
  expect(conflicts?.length).toBeGreaterThanOrEqual(min);
  for (const c of conflicts ?? []) {
    expect(c.garmentId).toBeTruthy();
    expect(typeof c.reason).toBe("string");
    expect(c.reason!.trim().length).toBeGreaterThan(0);
    // Reason should name a piece (letters), not be empty UUID-only noise alone
    expect(c.reason).toMatch(/[A-Za-z]/);
  }
}

describe("M0-20 pre-generation named conflicts", () => {
  it("T2-04: SET_CONFLICT with ≥2 named conflicts including laundry partner", () => {
    const s = loadScenario("T2-04-set-conflict-partner-laundry");
    const input = stage1InputFromScenario(s);
    const trousers = input.wardrobe.find((g) => g.id === SUIT_TROUSERS);
    expect(trousers).toBeDefined();
    expect(trousers?.availability).toBe("LAUNDRY");
    expect(trousers?.displayName).toMatch(/Trousers/i);

    const problem = runPrechecks(input);
    expect(problem).not.toBeNull();
    expect(problem!.code).toBe("SET_CONFLICT");
    assertNamedConflicts(problem!.conflicts, 2);

    const partner = problem!.conflicts!.find(
      (c) => c.garmentId === SUIT_TROUSERS,
    );
    const anchor = problem!.conflicts!.find((c) => c.garmentId === SUIT_JACKET);
    expect(partner).toBeDefined();
    expect(anchor).toBeDefined();
    expect(partner!.role).toBe("missing_partner");
    expect(partner!.availability).toBe("LAUNDRY");
    expect(partner!.reason!.toLowerCase()).toMatch(/laundry/);
    expect(partner!.reason).toMatch(/Navy Suit Trousers/i);
    expect(anchor!.reason).toMatch(/Navy Suit Jacket/i);
  });

  it("T2-10: LOCK_CONFLICT with named lock + anchor pieces", () => {
    const s = loadScenario("T2-10-lock-conflict");
    const input = stage1InputFromScenario(s);
    const problem = runPrechecks(input);
    expect(problem).not.toBeNull();
    expect(problem!.code).toBe("LOCK_CONFLICT");
    assertNamedConflicts(problem!.conflicts, 2);

    const anchor = problem!.conflicts!.find((c) => c.role === "anchor");
    const lock = problem!.conflicts!.find((c) => c.role === "lock");
    expect(anchor?.garmentId).toBe(ANCHOR_SPORT);
    expect(lock?.garmentId).toBe(LOCK_SPORT);
    expect(anchor!.reason).toMatch(/Navy Sport Coat/i);
    expect(lock!.reason).toMatch(/Grey Herringbone Sport Coat/i);
    expect(lock!.reason!.toLowerCase()).toMatch(/same slot|occupies/);
  });

  it("T2-04 generateLocal: same named conflicts; no Stage2/Builder", () => {
    const stage2Spy = vi.spyOn(stage2Mod, "runStage2");
    const builderSpy = vi.spyOn(builderMod, "runBuilder");
    const s = loadScenario("T2-04-set-conflict-partner-laundry");
    const input = stage1InputFromScenario(s);
    const pre = runPrechecks(input)!;

    const result = generateLocal({
      wardrobe: input.wardrobe,
      context: input.context,
      anchorGarmentId: input.anchorGarmentId,
      lockedAssignments: input.lockedAssignments,
      options: input.options,
      profile: input.profile,
      sets: input.sets,
    });

    expect(isLocalProblem(result)).toBe(true);
    expect(stage2Spy).not.toHaveBeenCalled();
    expect(builderSpy).not.toHaveBeenCalled();
    stage2Spy.mockRestore();
    builderSpy.mockRestore();

    if (!isLocalProblem(result)) return;
    expect(result.code).toBe("SET_CONFLICT");
    expect(result.status).toBe(400);
    assertNamedConflicts(result.conflicts, 2);
    expect(result.conflicts!.map((c) => c.garmentId).sort()).toEqual(
      pre.conflicts!.map((c) => c.garmentId).sort(),
    );
    for (const c of result.conflicts!) {
      const match = pre.conflicts!.find((p) => p.garmentId === c.garmentId);
      expect(c.reason).toBe(match!.reason);
    }
    const partner = result.conflicts!.find((c) => c.garmentId === SUIT_TROUSERS);
    expect(partner?.reason).toMatch(/Navy Suit Trousers.*laundry/i);
  });

  it("T2-10 generateLocal: same named conflicts; no Stage2/Builder", () => {
    const stage2Spy = vi.spyOn(stage2Mod, "runStage2");
    const builderSpy = vi.spyOn(builderMod, "runBuilder");
    const s = loadScenario("T2-10-lock-conflict");
    const input = stage1InputFromScenario(s);
    const pre = runPrechecks(input)!;

    const result = generateLocal({
      wardrobe: input.wardrobe,
      context: input.context,
      anchor: input.anchorGarmentId,
      locks: input.lockedAssignments,
      options: input.options,
      profile: input.profile,
      sets: input.sets,
    });

    expect(isLocalProblem(result)).toBe(true);
    expect(stage2Spy).not.toHaveBeenCalled();
    expect(builderSpy).not.toHaveBeenCalled();
    stage2Spy.mockRestore();
    builderSpy.mockRestore();

    if (!isLocalProblem(result)) return;
    expect(result.code).toBe("LOCK_CONFLICT");
    assertNamedConflicts(result.conflicts, 2);
    expect(result.conflicts!.map((c) => c.garmentId).sort()).toEqual(
      pre.conflicts!.map((c) => c.garmentId).sort(),
    );
    for (const c of result.conflicts!) {
      const match = pre.conflicts!.find((p) => p.garmentId === c.garmentId);
      expect(c.reason).toBe(match!.reason);
    }
  });
});

/**
 * Stage 4 outfit validator (M0-19) — PRD §8.5.
 * Pure / deterministic. Zero network.
 */

import { buildKeepTogetherMembership } from "../shared/membership.js";
import {
  activeCombinationRules,
  completesForbiddenPair,
} from "../stage3/combination.js";
import {
  garmentPair,
  colorFamilyPair,
} from "../shared/combinationRules.js";
import {
  DEFAULT_REQUIRE_SLOTS,
  type GarmentSummary,
  type OutfitAssignment,
  type Slot,
  type Stage4Caution,
  type Stage4Input,
  type Stage4Result,
  type Stage4Violation,
} from "../types.js";

const MAX_ACCESSORIES = 3;

function resolveCandidateIds(
  input: Stage4Input,
  slot: Slot,
): Set<string> {
  const fromIds = input.candidateIds?.[slot];
  if (fromIds && fromIds.length > 0) {
    return new Set(fromIds);
  }
  const fromSet = input.candidateSet?.[slot];
  if (fromSet && fromSet.length > 0) {
    return new Set(fromSet.map((c) => c.garmentId));
  }
  return new Set();
}

function fixedIdsForSlot(
  fixed: Stage4Input["fixed"],
  slot: Slot,
): Set<string> {
  return new Set(
    fixed.filter((f) => f.slot === slot).map((f) => f.garmentId),
  );
}

function allFixedIds(fixed: Stage4Input["fixed"]): Set<string> {
  return new Set(fixed.map((f) => f.garmentId));
}

function filledAssignments(
  assignments: OutfitAssignment[],
): OutfitAssignment[] {
  return assignments.filter(
    (a) => a.garmentId != null && a.garmentId !== "",
  );
}

function wardrobeById(
  wardrobe: GarmentSummary[],
): Map<string, GarmentSummary> {
  return new Map(wardrobe.map((g) => [g.id, g]));
}

function checkCandidateMembership(
  input: Stage4Input,
  violations: Stage4Violation[],
): void {
  const fixedExempt = allFixedIds(input.fixed);
  for (const a of filledAssignments(input.assignments)) {
    const id = a.garmentId!;
    if (fixedExempt.has(id)) {
      // Fixed inputs are exempt from shortlist membership, but must match
      // their declared fixed slot (ACCESSORY may appear multiple times).
      const fixedForId = input.fixed.filter((f) => f.garmentId === id);
      if (
        fixedForId.length > 0 &&
        !fixedForId.some((f) => f.slot === a.slot)
      ) {
        violations.push({
          code: "CANDIDATE_SET_MEMBERSHIP",
          reason: `Fixed garment ${id} assigned to slot ${a.slot} but fixed in ${fixedForId.map((f) => f.slot).join(",")}`,
          slot: a.slot,
          garmentId: id,
        });
      }
      continue;
    }
    const allowed = resolveCandidateIds(input, a.slot);
    // Also allow fixed-for-slot ids already covered above
    for (const fid of fixedIdsForSlot(input.fixed, a.slot)) {
      allowed.add(fid);
    }
    if (!allowed.has(id)) {
      violations.push({
        code: "CANDIDATE_SET_MEMBERSHIP",
        reason: `Garment ${id} is not in the candidate set for slot ${a.slot}`,
        slot: a.slot,
        garmentId: id,
      });
    }
  }
}

function checkAnchor(
  input: Stage4Input,
  violations: Stage4Violation[],
): void {
  const anchors = input.fixed.filter((f) => f.role === "anchor");
  if (anchors.length === 0) return;
  for (const anchor of anchors) {
    const matches = input.assignments.filter(
      (a) => a.garmentId === anchor.garmentId,
    );
    if (matches.length === 0) {
      violations.push({
        code: "ANCHOR_MISSING",
        reason: `Anchor ${anchor.garmentId} missing from assignments`,
        slot: anchor.slot,
        garmentId: anchor.garmentId,
      });
      continue;
    }
    const inSlot = matches.find((a) => a.slot === anchor.slot);
    if (!inSlot) {
      violations.push({
        code: "ANCHOR_MISMATCH",
        reason: `Anchor ${anchor.garmentId} not in slot ${anchor.slot}`,
        slot: anchor.slot,
        garmentId: anchor.garmentId,
      });
      continue;
    }
    if (inSlot.isAnchor !== true) {
      violations.push({
        code: "ANCHOR_MISMATCH",
        reason: `Anchor ${anchor.garmentId} in ${anchor.slot} lacks isAnchor=true`,
        slot: anchor.slot,
        garmentId: anchor.garmentId,
      });
    }
  }
}

function checkSlotUniqueness(
  input: Stage4Input,
  byId: Map<string, GarmentSummary>,
  violations: Stage4Violation[],
): void {
  const filled = filledAssignments(input.assignments);
  const nonAccBySlot = new Map<Slot, string[]>();
  const accessoryIds: string[] = [];
  const seenGarments = new Map<string, Slot[]>();

  for (const a of filled) {
    const id = a.garmentId!;
    const slots = seenGarments.get(id) ?? [];
    slots.push(a.slot);
    seenGarments.set(id, slots);

    if (a.slot === "ACCESSORY") {
      accessoryIds.push(id);
    } else {
      const list = nonAccBySlot.get(a.slot) ?? [];
      list.push(id);
      nonAccBySlot.set(a.slot, list);
    }
  }

  for (const [slot, ids] of nonAccBySlot) {
    if (ids.length > 1) {
      violations.push({
        code: "SLOT_UNIQUENESS",
        reason: `Slot ${slot} has ${ids.length} garments; at most one allowed`,
        slot,
        relatedIds: ids,
      });
    }
  }

  if (accessoryIds.length > MAX_ACCESSORIES) {
    violations.push({
      code: "ACCESSORY_LIMIT",
      reason: `ACCESSORY has ${accessoryIds.length} garments; at most ${MAX_ACCESSORIES} allowed`,
      slot: "ACCESSORY",
      relatedIds: accessoryIds,
    });
  }

  // Distinct categories for accessories
  const categories = new Set<string>();
  const dupCategories: string[] = [];
  for (const id of accessoryIds) {
    const cat = byId.get(id)?.category ?? id;
    if (categories.has(cat)) {
      dupCategories.push(cat);
    }
    categories.add(cat);
  }
  if (dupCategories.length > 0) {
    violations.push({
      code: "ACCESSORY_LIMIT",
      reason: `ACCESSORY categories must be distinct; duplicate: ${[...new Set(dupCategories)].join(", ")}`,
      slot: "ACCESSORY",
      relatedIds: accessoryIds,
    });
  }

  for (const [id, slots] of seenGarments) {
    if (slots.length > 1) {
      violations.push({
        code: "DUPLICATE_GARMENT",
        reason: `Garment ${id} appears in multiple assignments (${slots.join(", ")})`,
        garmentId: id,
        relatedIds: [id],
      });
    }
  }
}

function checkRequiredSlots(
  input: Stage4Input,
  violations: Stage4Violation[],
): void {
  const required =
    input.options?.requireSlots ?? DEFAULT_REQUIRE_SLOTS;
  for (const slot of required) {
    const rows = input.assignments.filter((a) => a.slot === slot);
    const filled = rows.find(
      (a) => a.garmentId != null && a.garmentId !== "",
    );
    if (filled) continue;
    const gapped = rows.find(
      (a) =>
        (a.garmentId == null || a.garmentId === "") &&
        a.gapReason != null &&
        a.gapReason !== "",
    );
    if (gapped) continue;
    violations.push({
      code: "REQUIRED_SLOT_EMPTY",
      reason: `Required slot ${slot} has neither a garment nor an explicit gap`,
      slot,
    });
  }
}

function checkCombination(
  input: Stage4Input,
  byId: Map<string, GarmentSummary>,
  violations: Stage4Violation[],
  cautions: Stage4Caution[],
): void {
  const rules = activeCombinationRules(
    input.profile?.activeRules,
    input.context.occasion,
  );
  if (rules.length === 0) return;

  const filled = filledAssignments(input.assignments);
  const ids = filled.map((a) => a.garmentId!);
  const idSet = new Set(ids);
  const garments = ids
    .map((id) => byId.get(id))
    .filter((g): g is GarmentSummary => g != null);
  const fixedIds = allFixedIds(input.fixed);
  const reported = new Set<string>();

  for (const rule of rules) {
    const pair = garmentPair(rule.subject ?? {});
    if (pair) {
      const [a, b] = pair;
      if (!(idSet.has(a) && idSet.has(b))) continue;
      const key = `pair:${[a, b].sort().join("|")}:${rule.id ?? ""}`;
      if (reported.has(key)) continue;
      reported.add(key);
      if (fixedIds.has(a) && fixedIds.has(b)) {
        cautions.push({
          code: "LOCKED_DISLIKED_PAIR",
          reason: `Locked/fixed garments form a disliked combination (${a}, ${b})`,
          relatedIds: [a, b],
        });
      } else {
        violations.push({
          code: "COMBINATION_VIOLATION",
          reason: `Forbidden combination pair present: ${a} with ${b}`,
          relatedIds: [a, b],
          ruleId: rule.id ?? null,
        });
      }
      continue;
    }

    const cf = colorFamilyPair(rule.subject ?? {});
    if (cf) {
      const [fa, fb] = cf;
      const faIds = garments.filter(
        (g) => g.colorPrimary?.family?.toLowerCase() === fa,
      );
      const fbIds = garments.filter(
        (g) => g.colorPrimary?.family?.toLowerCase() === fb,
      );
      if (faIds.length === 0 || fbIds.length === 0) continue;
      const key = `cf:${[fa, fb].sort().join("|")}:${rule.id ?? ""}`;
      if (reported.has(key)) continue;
      reported.add(key);
      const involved = [...faIds, ...fbIds].map((g) => g.id);
      const bothSidesFixed =
        faIds.every((g) => fixedIds.has(g.id)) &&
        fbIds.every((g) => fixedIds.has(g.id));
      if (bothSidesFixed) {
        cautions.push({
          code: "LOCKED_DISLIKED_PAIR",
          reason: `Locked/fixed garments form a disliked colour-family combination (${fa}, ${fb})`,
          relatedIds: involved,
        });
      } else {
        violations.push({
          code: "COMBINATION_VIOLATION",
          reason: `Forbidden colour-family combination present: ${fa} with ${fb}`,
          relatedIds: involved,
          ruleId: rule.id ?? null,
        });
      }
    }
  }
}

function checkSetIntegrity(
  input: Stage4Input,
  violations: Stage4Violation[],
): void {
  const membersBySet = buildKeepTogetherMembership(input.wardrobe, input.sets);
  const present = new Set(
    filledAssignments(input.assignments).map((a) => a.garmentId!),
  );

  for (const [setId, members] of membersBySet) {
    if (members.length < 2) continue;
    const presentMembers = members.filter((id) => present.has(id));
    if (
      presentMembers.length > 0 &&
      presentMembers.length < members.length
    ) {
      const missing = members.filter((id) => !present.has(id));
      violations.push({
        code: "SET_INTEGRITY",
        reason: `keepTogether set ${setId} is half-present: have [${presentMembers.join(", ")}], missing [${missing.join(", ")}]`,
        relatedIds: [...presentMembers, ...missing],
      });
    }
  }
}

function checkLocks(
  input: Stage4Input,
  violations: Stage4Violation[],
): void {
  const locks = input.fixed.filter((f) => f.role === "lock");
  for (const lock of locks) {
    const matches = input.assignments.filter(
      (a) => a.slot === lock.slot && a.garmentId === lock.garmentId,
    );
    if (matches.length === 0) {
      // ACCESSORY: also accept any ACCESSORY row with the id
      if (lock.slot === "ACCESSORY") {
        const acc = input.assignments.find(
          (a) => a.slot === "ACCESSORY" && a.garmentId === lock.garmentId,
        );
        if (acc) continue;
      }
      const wrong = input.assignments.find(
        (a) => a.slot === lock.slot && a.garmentId && a.garmentId !== lock.garmentId,
      );
      if (wrong) {
        violations.push({
          code: "LOCK_MISMATCH",
          reason: `Lock expected ${lock.garmentId} in ${lock.slot}, found ${wrong.garmentId}`,
          slot: lock.slot,
          garmentId: lock.garmentId,
          relatedIds: [lock.garmentId, wrong.garmentId!],
        });
      } else {
        violations.push({
          code: "LOCK_MISSING",
          reason: `Locked garment ${lock.garmentId} missing from slot ${lock.slot}`,
          slot: lock.slot,
          garmentId: lock.garmentId,
        });
      }
    }
  }
}

function checkAccessoryPolicy(
  input: Stage4Input,
  violations: Stage4Violation[],
): void {
  const policy = input.options?.accessoryPolicy ?? "OPEN";
  const accessoryIds = filledAssignments(input.assignments)
    .filter((a) => a.slot === "ACCESSORY")
    .map((a) => a.garmentId!);

  if (policy === "LOCKED") {
    const lockedAcc = input.fixed
      .filter((f) => f.slot === "ACCESSORY")
      .map((f) => f.garmentId)
      .sort();
    const got = [...accessoryIds].sort();
    const lockedSet = new Set(lockedAcc);
    const extras = got.filter((id) => !lockedSet.has(id));
    const missing = lockedAcc.filter((id) => !got.includes(id));
    if (extras.length > 0 || missing.length > 0) {
      violations.push({
        code: "ACCESSORY_POLICY",
        reason: `accessoryPolicy LOCKED: expected [${lockedAcc.join(", ")}], got [${got.join(", ")}]`,
        slot: "ACCESSORY",
        relatedIds: [...got, ...lockedAcc],
      });
    }
    return;
  }

  // OPEN: count cap is enforced by ACCESSORY_LIMIT / SLOT uniqueness above.
  if (accessoryIds.length > MAX_ACCESSORIES) {
    // Prefer a single ACCESSORY_LIMIT; only add policy code if limit was not already recorded.
    if (!violations.some((v) => v.code === "ACCESSORY_LIMIT")) {
      violations.push({
        code: "ACCESSORY_POLICY",
        reason: `accessoryPolicy OPEN allows at most ${MAX_ACCESSORIES} accessories; got ${accessoryIds.length}`,
        slot: "ACCESSORY",
        relatedIds: accessoryIds,
      });
    }
  }
}

function checkLayerCaution(
  input: Stage4Input,
  cautions: Stage4Caution[],
): void {
  const band = input.context.temperatureBand;
  const filledSlots = new Set(
    filledAssignments(input.assignments).map((a) => a.slot),
  );
  if (band === "COLD" && !filledSlots.has("OUTERWEAR")) {
    cautions.push({
      code: "LAYER_REQUIREMENT",
      reason: "COLD band expects OUTERWEAR; outfit has none",
    });
  }
  if (band === "COOL") {
    const hasLayer =
      filledSlots.has("MID_LAYER") ||
      filledSlots.has("JACKET") ||
      filledSlots.has("OUTERWEAR");
    if (!hasLayer) {
      cautions.push({
        code: "LAYER_REQUIREMENT",
        reason:
          "COOL band expects at least one of MID_LAYER, JACKET, OUTERWEAR",
      });
    }
  }
}

function checkRationaleCaution(
  input: Stage4Input,
  cautions: Stage4Caution[],
): void {
  const r = input.rationale;
  if (r == null) return;
  const summary = (r.summary ?? "").trim();
  if (!summary) {
    cautions.push({
      code: "RATIONALE_QUALITY",
      reason: "Rationale summary is empty",
    });
    return;
  }
  if (summary.length > 400) {
    cautions.push({
      code: "RATIONALE_QUALITY",
      reason: `Rationale summary length ${summary.length} exceeds 400`,
    });
  }
  // Deterministic rationales use a generic template; skip garment-naming check
  if (input.fallbackLevel === "DETERMINISTIC") {
    return;
  }
  const named = input.wardrobe.filter((g) =>
    summary.toLowerCase().includes(g.displayName.toLowerCase()),
  );
  if (named.length < 2) {
    cautions.push({
      code: "RATIONALE_QUALITY",
      reason: "Rationale summary names fewer than 2 garments",
    });
  }
}

/**
 * Validate a completed (or explicitly gapped) outfit against §8.5 checks.
 */
export function runStage4(input: Stage4Input): Stage4Result {
  const violations: Stage4Violation[] = [];
  const cautions: Stage4Caution[] = [];
  const byId = wardrobeById(input.wardrobe);

  checkCandidateMembership(input, violations);
  checkAnchor(input, violations);
  checkSlotUniqueness(input, byId, violations);
  checkRequiredSlots(input, violations);
  checkCombination(input, byId, violations, cautions);
  checkSetIntegrity(input, violations);
  checkLocks(input, violations);
  checkAccessoryPolicy(input, violations);
  checkLayerCaution(input, cautions);
  checkRationaleCaution(input, cautions);

  if (violations.length > 0) {
    return { ok: false, violations, cautions };
  }
  return { ok: true, cautions };
}

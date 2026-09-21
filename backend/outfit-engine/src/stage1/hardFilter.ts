import {
  passesFiltersAtTier,
  TIER0,
  type FilterTier,
} from "./filters.js";
import {
  filterTierForLadder,
  relaxationForStep,
  type LadderTier,
} from "./ladder.js";
import { partnerIdsFor, runPrechecks } from "./prechecks.js";
import { buildKeepTogetherMembership } from "../shared/membership.js";
import {
  ALL_SLOTS,
  DEFAULT_REQUIRE_SLOTS,
  type GarmentSummary,
  type PreferenceRule,
  type Slot,
  type Stage1Input,
  type Stage1Output,
  type Stage1Result,
} from "../types.js";

function stableSort(garments: GarmentSummary[]): GarmentSummary[] {
  return [...garments].sort((a, b) => a.id.localeCompare(b.id));
}

function occupiedSlots(input: Stage1Input): Map<Slot, string[]> {
  const occupied = new Map<Slot, string[]>();
  const add = (slot: Slot, id: string) => {
    const list = occupied.get(slot) ?? [];
    if (!list.includes(id)) list.push(id);
    occupied.set(slot, list);
  };

  if (input.anchorGarmentId) {
    const anchor = input.wardrobe.find((g) => g.id === input.anchorGarmentId);
    if (anchor) add(anchor.slot, anchor.id);
  }
  for (const lock of input.lockedAssignments ?? []) {
    if (!lock.garmentId) continue;
    const g = input.wardrobe.find((x) => x.id === lock.garmentId);
    if (!g) continue;
    add((lock.slot ?? g.slot) as Slot, g.id);
  }
  return occupied;
}

/**
 * keepTogether atomicity: every member must pass the same tier filters,
 * otherwise no member of the set is eligible.
 */
function applySetAtomicity(
  candidates: GarmentSummary[],
  wardrobe: GarmentSummary[],
  membersBySet: Map<string, string[]>,
  context: Stage1Input["context"],
  rules: PreferenceRule[],
  tier: FilterTier,
): GarmentSummary[] {
  const wardrobeById = new Map(wardrobe.map((g) => [g.id, g]));
  const rejectedSets = new Set<string>();

  for (const g of candidates) {
    if (!g.setId) continue;
    const members = membersBySet.get(g.setId) ?? [g.id];
    const isKeepTogether =
      g.keepTogether === true || members.length > 1;
    if (!isKeepTogether) continue;

    let allOk = true;
    for (const mid of members) {
      const m = wardrobeById.get(mid);
      if (!m || !passesFiltersAtTier(m, context, rules, tier)) {
        allOk = false;
        break;
      }
    }
    if (!allOk) rejectedSets.add(g.setId);
  }

  if (rejectedSets.size === 0) return candidates;
  return candidates.filter((g) => !g.setId || !rejectedSets.has(g.setId));
}

function slotIsOccupiedByFixed(
  slot: Slot,
  occupied: Map<Slot, string[]>,
): boolean {
  if (slot === "ACCESSORY") return false;
  return (occupied.get(slot)?.length ?? 0) > 0;
}

function accessoryCategoriesTaken(
  occupied: Map<Slot, string[]>,
  wardrobeById: Map<string, GarmentSummary>,
): Set<string> {
  const cats = new Set<string>();
  for (const id of occupied.get("ACCESSORY") ?? []) {
    const g = wardrobeById.get(id);
    if (g?.category) cats.add(g.category);
  }
  return cats;
}

function filterSlotCandidates(
  wardrobe: GarmentSummary[],
  slot: Slot,
  input: Stage1Input,
  rules: PreferenceRule[],
  tier: FilterTier,
  occupied: Map<Slot, string[]>,
  membersBySet: Map<string, string[]>,
): GarmentSummary[] {
  const wardrobeById = new Map(wardrobe.map((g) => [g.id, g]));
  const fixedIds = new Set<string>();
  for (const ids of occupied.values()) for (const id of ids) fixedIds.add(id);

  const takenAccessoryCats = accessoryCategoriesTaken(occupied, wardrobeById);
  const accessoryCount = occupied.get("ACCESSORY")?.length ?? 0;

  let candidates = wardrobe.filter((g) => {
    if (g.slot !== slot) return false;
    if (fixedIds.has(g.id)) return false;
    if (slot !== "ACCESSORY" && slotIsOccupiedByFixed(slot, occupied)) {
      return false;
    }
    if (slot === "ACCESSORY") {
      if (accessoryCount >= 3) return false;
      if (g.category && takenAccessoryCats.has(g.category)) return false;
    }
    return passesFiltersAtTier(g, input.context, rules, tier);
  });

  candidates = applySetAtomicity(
    candidates,
    wardrobe,
    membersBySet,
    input.context,
    rules,
    tier,
  );

  return stableSort(candidates);
}

const MAX_TIER: FilterTier = { formalityDelta: 2, warmthWiden: 1 };

/** True if any garment in slot could become eligible via formality/warmth ladder. */
function canLadderHelp(
  sameSlot: GarmentSummary[],
  input: Stage1Input,
  rules: PreferenceRule[],
): boolean {
  return sameSlot.some((g) =>
    passesFiltersAtTier(g, input.context, rules, MAX_TIER),
  );
}

function promoteSetPartners(
  eligibleGarments: Record<Slot, GarmentSummary[]>,
  eligible: Record<Slot, string[]>,
  wardrobe: GarmentSummary[],
  membersBySet: Map<string, string[]>,
  context: Stage1Input["context"],
  rules: PreferenceRule[],
): void {
  const wardrobeById = new Map(wardrobe.map((g) => [g.id, g]));
  const allEligibleIds = new Set(
    Object.values(eligible).flatMap((ids) => ids),
  );

  for (const id of [...allEligibleIds]) {
    const partners = partnerIdsFor(id, wardrobe, membersBySet);
    for (const pid of partners) {
      if (allEligibleIds.has(pid)) continue;
      const p = wardrobeById.get(pid);
      if (!p) continue;
      if (!passesFiltersAtTier(p, context, rules, TIER0)) continue;
      eligibleGarments[p.slot] = stableSort([
        ...eligibleGarments[p.slot].filter((g) => g.id !== p.id),
        p,
      ]);
      eligible[p.slot] = eligibleGarments[p.slot].map((g) => g.id);
      allEligibleIds.add(pid);
    }
  }
}

/**
 * Stage 1 hard filters — deterministic, no network.
 */
export function runStage1(input: Stage1Input): Stage1Output {
  const pre = runPrechecks(input);
  if (pre) return pre;

  const rules = (input.profile?.activeRules ?? []) as PreferenceRule[];
  const requireSlots = input.options?.requireSlots ?? DEFAULT_REQUIRE_SLOTS;
  const membersBySet = buildKeepTogetherMembership(input.wardrobe, input.sets);
  const occupied = occupiedSlots(input);

  const eligibleGarments = {} as Record<Slot, GarmentSummary[]>;
  const eligible = {} as Record<Slot, string[]>;
  for (const slot of ALL_SLOTS) {
    eligibleGarments[slot] = [];
    eligible[slot] = [];
  }

  const relaxationsApplied: Stage1Result["relaxationsApplied"] = [];
  const gaps: Slot[] = [];

  const fixed: Stage1Result["fixed"] = [];
  if (input.anchorGarmentId) {
    const anchor = input.wardrobe.find((g) => g.id === input.anchorGarmentId);
    if (anchor) {
      fixed.push({ garmentId: anchor.id, slot: anchor.slot, role: "anchor" });
      eligibleGarments[anchor.slot] = [anchor];
      eligible[anchor.slot] = [anchor.id];
    }
  }
  for (const lock of input.lockedAssignments ?? []) {
    if (!lock.garmentId) continue;
    const g = input.wardrobe.find((x) => x.id === lock.garmentId);
    if (!g) continue;
    const slot = (lock.slot ?? g.slot) as Slot;
    if (fixed.some((f) => f.garmentId === g.id)) continue;
    fixed.push({ garmentId: g.id, slot, role: "lock" });
    eligibleGarments[slot] = stableSort([
      ...eligibleGarments[slot].filter((x) => x.id !== g.id),
      g,
    ]);
    eligible[slot] = eligibleGarments[slot].map((x) => x.id);
  }

  for (const slot of ALL_SLOTS) {
    if (slot !== "ACCESSORY" && slotIsOccupiedByFixed(slot, occupied)) {
      continue;
    }

    const required = requireSlots.includes(slot);
    let candidates = filterSlotCandidates(
      input.wardrobe,
      slot,
      input,
      rules,
      TIER0,
      occupied,
      membersBySet,
    );

    if (candidates.length === 0 && required) {
      const sameSlot = input.wardrobe.filter((g) => g.slot === slot);
      const ladderHelps = canLadderHelp(sameSlot, input, rules);

      // Unavailable-only (or never-relax / season failures): immediate gap (D-25).
      if (!ladderHelps) {
        relaxationsApplied.push(relaxationForStep(3, slot));
        gaps.push(slot);
      } else {
        // Climb: FORMALITY_WIDENED → WARMTH_WIDENED → SLOT_ABANDONED
        let tier: LadderTier = 0;
        while (candidates.length === 0 && tier < 3) {
          tier = (tier + 1) as LadderTier;
          relaxationsApplied.push(relaxationForStep(tier as 1 | 2 | 3, slot));
          const next = filterTierForLadder(tier);
          if (next == null) {
            gaps.push(slot);
            break;
          }
          candidates = filterSlotCandidates(
            input.wardrobe,
            slot,
            input,
            rules,
            next,
            occupied,
            membersBySet,
          );
        }
      }
    }

    const fixedHere = eligibleGarments[slot].filter((g) =>
      fixed.some((f) => f.garmentId === g.id),
    );
    const merged = stableSort([
      ...fixedHere,
      ...candidates.filter((c) => !fixedHere.some((f) => f.id === c.id)),
    ]);
    // For optional empty slots, leave empty (not a gap)
    if (!(required && gaps.includes(slot) && merged.length === 0)) {
      eligibleGarments[slot] = merged;
      eligible[slot] = merged.map((g) => g.id);
    } else {
      eligibleGarments[slot] = fixedHere;
      eligible[slot] = fixedHere.map((g) => g.id);
    }
  }

  promoteSetPartners(
    eligibleGarments,
    eligible,
    input.wardrobe,
    membersBySet,
    input.context,
    rules,
  );

  return {
    ok: true,
    eligible,
    eligibleGarments,
    relaxationsApplied,
    gaps,
    fixed,
  };
}

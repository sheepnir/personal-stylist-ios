import { isArchived, isAvailable, isOwned, isReady, passesNeverRelax } from "./filters.js";
import { buildKeepTogetherMembership } from "../shared/membership.js";
import type {
  GarmentSummary,
  Slot,
  Stage1Conflict,
  Stage1Input,
  Stage1Problem,
} from "../types.js";

function byId(wardrobe: GarmentSummary[]): Map<string, GarmentSummary> {
  return new Map(wardrobe.map((g) => [g.id, g]));
}

/** Human label for a piece — displayName when known, else raw id. */
export function pieceLabel(
  garment: GarmentSummary | undefined,
  garmentId: string,
): string {
  const name = garment?.displayName?.trim();
  return name && name.length > 0 ? name : garmentId;
}

/** One-clause human reason when a garment fails never-relax. */
export function neverRelaxConflictReason(
  garment: GarmentSummary,
  garmentId: string,
): string {
  const name = pieceLabel(garment, garmentId);
  if (garment.readiness === "DRAFT" || !isReady(garment)) {
    return `${name} is still a draft`;
  }
  const avail = garment.availability ?? "AVAILABLE";
  if (avail === "LAUNDRY") {
    // Match OpenAPI / product copy for laundry partners (e.g. trousers).
    return `${name} are in laundry`;
  }
  if (!isAvailable(garment)) {
    return `${name} is unavailable (${avail})`;
  }
  if (!isOwned(garment)) {
    return `${name} is not owned`;
  }
  if (isArchived(garment)) {
    return `${name} is archived`;
  }
  return `${name} fails never-relax filters`;
}

function conflict(partial: Stage1Conflict): Stage1Conflict {
  return { ...partial, reason: partial.reason ?? `Conflict involving ${partial.garmentId}` };
}

export function partnerIdsFor(
  garmentId: string,
  wardrobe: GarmentSummary[],
  membersBySet: Map<string, string[]>,
): string[] {
  const g = wardrobe.find((x) => x.id === garmentId);
  if (!g?.setId || !g.keepTogether) {
    // Still check sets map if another garment marks keepTogether
    for (const [, members] of membersBySet) {
      if (members.includes(garmentId) && members.length > 1) {
        return members.filter((id) => id !== garmentId);
      }
    }
    return [];
  }
  const members = membersBySet.get(g.setId) ?? [garmentId];
  return members.filter((id) => id !== garmentId);
}

function problem(
  code: Stage1Problem["code"],
  detail: string,
  conflicts?: Stage1Conflict[],
): Stage1Problem {
  const titles: Record<Stage1Problem["code"], string> = {
    LOCK_CONFLICT: "Lock conflict",
    SET_CONFLICT: "Set conflict",
    GARMENT_NOT_READY: "Garment not ready",
  };
  return {
    ok: false,
    code,
    title: titles[code],
    status: 400,
    detail,
    conflicts: conflicts?.map((c) => conflict(c)),
  };
}

/**
 * Pre-checks before building eligible maps (design §3).
 * Returns a Problem or null if OK.
 * Every conflicts[] entry includes garmentId + human reason naming the piece.
 */
export function runPrechecks(input: Stage1Input): Stage1Problem | null {
  const wardrobe = input.wardrobe ?? [];
  const rules = (input.profile?.activeRules ?? []).filter(
    (r) => r.active !== false,
  );
  const occasion = input.context.occasion;
  const index = byId(wardrobe);
  const membersBySet = buildKeepTogetherMembership(wardrobe, input.sets);

  // 4. Draft in wardrobe payload → GARMENT_NOT_READY (D-23)
  const draft = wardrobe.find((g) => g.readiness === "DRAFT");
  if (draft) {
    const name = pieceLabel(draft, draft.id);
    return problem(
      "GARMENT_NOT_READY",
      `Wardrobe contains draft garment ${name}; drafts never enter generation (D-23).`,
      [
        {
          garmentId: draft.id,
          role: "draft",
          reason: `${name} is still a draft`,
        },
      ],
    );
  }

  const anchorId = input.anchorGarmentId ?? null;
  let anchor: GarmentSummary | undefined;
  if (anchorId) {
    anchor = index.get(anchorId);
    if (!anchor) {
      return problem(
        "LOCK_CONFLICT",
        `Anchor garment ${anchorId} is not present in wardrobe.`,
        [
          {
            garmentId: anchorId,
            role: "anchor",
            reason: `Anchor ${anchorId} is not present in wardrobe`,
          },
        ],
      );
    }
    if (!passesNeverRelax(anchor, rules, occasion)) {
      const name = pieceLabel(anchor, anchorId);
      const code =
        anchor.readiness === "DRAFT" ? "GARMENT_NOT_READY" : "LOCK_CONFLICT";
      return problem(
        code,
        `Anchor garment ${name} fails never-relax filters (availability/readiness/ownership/rules).`,
        [
          {
            garmentId: anchorId,
            role: "anchor",
            slot: anchor.slot,
            availability: anchor.availability,
            reason: neverRelaxConflictReason(anchor, anchorId),
          },
        ],
      );
    }
  }

  const locks = input.lockedAssignments ?? [];
  const seenSlots = new Map<Slot, string>();
  const accessoryLockCategories = new Map<string, string>();
  
  for (const lock of locks) {
    if (!lock.garmentId) continue;
    const g = index.get(lock.garmentId);
    if (!g) {
      return problem(
        "LOCK_CONFLICT",
        `Locked garment ${lock.garmentId} is not present in wardrobe.`,
        [
          {
            garmentId: lock.garmentId,
            role: "lock",
            slot: lock.slot,
            reason: `Locked ${lock.garmentId} is not present in wardrobe`,
          },
        ],
      );
    }
    if (!passesNeverRelax(g, rules, occasion)) {
      const name = pieceLabel(g, lock.garmentId);
      const code =
        g.readiness === "DRAFT" ? "GARMENT_NOT_READY" : "LOCK_CONFLICT";
      return problem(
        code,
        `Locked garment ${name} fails never-relax filters.`,
        [
          {
            garmentId: lock.garmentId,
            role: "lock",
            slot: g.slot,
            availability: g.availability,
            reason: neverRelaxConflictReason(g, lock.garmentId),
          },
        ],
      );
    }

    // Issue #31-2: Validate lock.slot matches garment.slot when both present
    if (lock.slot && lock.slot !== g.slot) {
      const name = pieceLabel(g, lock.garmentId);
      return problem(
        "LOCK_CONFLICT",
        `Lock slot mismatch: ${name} is ${g.slot}, but lock specifies ${lock.slot} (D-32).`,
        [
          {
            garmentId: lock.garmentId,
            role: "lock",
            slot: lock.slot,
            reason: `${name} lock slot ${lock.slot} does not match garment slot ${g.slot}`,
          },
        ],
      );
    }

    // D-32: Track ACCESSORY lock categories to check for duplicates
    if (g.slot === "ACCESSORY" && g.category) {
      const cat = String(g.category).toUpperCase();
      const existingId = accessoryLockCategories.get(cat);
      if (existingId) {
        const existing = index.get(existingId)!;
        const existingName = pieceLabel(existing, existingId);
        const lockName = pieceLabel(g, g.id);
        return problem(
          "LOCK_CONFLICT",
          `LOCK_CONFLICT: multiple locked accessories of category ${cat} (D-32: distinct categories required).`,
          [
            {
              garmentId: existingId,
              role: "lock",
              slot: "ACCESSORY",
              reason: `Locked ${existingName} (${cat}) conflicts with another ${cat} lock`,
            },
            {
              garmentId: g.id,
              role: "lock",
              slot: "ACCESSORY",
              reason: `Locked ${lockName} (${cat}) duplicates category of another lock`,
            },
          ],
        );
      }
      accessoryLockCategories.set(cat, g.id);
    }
    // Lock slot must match garment slot
    const lockSlot = (lock.slot ?? g.slot) as Slot;

    // Issue #31-1: Check if locking the anchor BEFORE checking slot conflicts
    if (anchorId && lock.garmentId === anchorId) {
      // locking the anchor itself is fine / redundant
      continue;
    }

    if (anchor && lockSlot === anchor.slot) {
      // D-32: ACCESSORY can hold up to 3 of distinct categories
      // Allow ACCESSORY lock + ACCESSORY anchor if categories differ
      if (lockSlot === "ACCESSORY" && anchor.slot === "ACCESSORY") {
        const anchorCat = anchor.category ? String(anchor.category).toUpperCase() : null;
        const lockCat = g.category ? String(g.category).toUpperCase() : null;
        if (anchorCat && lockCat && anchorCat === lockCat) {
          const anchorName = pieceLabel(anchor, anchor.id);
          const lockName = pieceLabel(g, g.id);
          return problem(
            "LOCK_CONFLICT",
            `LOCK_CONFLICT: locked ${lockName} and anchor ${anchorName} are both ${lockCat} accessories (D-32: distinct categories required).`,
            [
              {
                garmentId: anchor.id,
                role: "anchor",
                slot: anchor.slot,
                reason: `Anchor ${anchorName} (${lockCat}) conflicts with same-category lock`,
              },
              {
                garmentId: g.id,
                role: "lock",
                slot: lockSlot,
                reason: `Locked ${lockName} (${lockCat}) is the same accessory category as the anchor`,
              },
            ],
          );
        }
        // Different categories or null category — allow
        continue;
      }
      // Non-ACCESSORY: same-slot conflict
      const anchorName = pieceLabel(anchor, anchor.id);
      const lockName = pieceLabel(g, g.id);
      return problem(
        "LOCK_CONFLICT",
        `LOCK_CONFLICT: locked ${lockName} occupies the same slot as anchor ${anchorName} (D-32).`,
        [
          {
            garmentId: anchor.id,
            role: "anchor",
            slot: anchor.slot,
            reason: `Anchor ${anchorName} conflicts with a lock in ${anchor.slot}`,
          },
          {
            garmentId: g.id,
            role: "lock",
            slot: lockSlot,
            reason: `Locked ${lockName} occupies the same slot as the anchor garment`,
          },
        ],
      );
    }

    // Issue #31-3: Reject duplicate non-accessory slot locks
    if (lockSlot !== "ACCESSORY") {
      const existing = seenSlots.get(lockSlot);
      if (existing) {
        const existingGarment = index.get(existing);
        const existingName = pieceLabel(existingGarment, existing);
        const lockName = pieceLabel(g, lock.garmentId);
        return problem(
          "LOCK_CONFLICT",
          `Two locks in non-accessory slot ${lockSlot}: ${existingName} and ${lockName} (D-32).`,
          [
            {
              garmentId: existing,
              role: "lock",
              slot: lockSlot,
              reason: `${existingName} already locked in ${lockSlot}`,
            },
            {
              garmentId: lock.garmentId,
              role: "lock",
              slot: lockSlot,
              reason: `${lockName} cannot be locked; ${lockSlot} already has a lock`,
            },
          ],
        );
      }
      seenSlots.set(lockSlot, lock.garmentId);
    }
  }

  // Issue #31-4: Reject locks that occupy a keepTogether partner's slot with a different garment
  // Build set of slots claimed by keepTogether partners of anchor/locks
  const partnerSlotClaims = new Map<Slot, { setMemberId: string; partnerId: string }>();
  
  const checkForPartnerSlotConflicts = (garmentId: string, role: "anchor" | "lock") => {
    const g = index.get(garmentId);
    if (!g) return;
    
    const partners = partnerIdsFor(garmentId, wardrobe, membersBySet);
    if (partners.length === 0) return;
    
    const inKeepTogether =
      g.keepTogether === true ||
      [...membersBySet.values()].some(
        (m) => m.includes(garmentId) && m.length > 1,
      );
    if (!inKeepTogether) return;

    for (const pid of partners) {
      const partner = index.get(pid);
      if (!partner) continue;
      
      // Record that this partner's slot is claimed
      partnerSlotClaims.set(partner.slot, { setMemberId: garmentId, partnerId: pid });
    }
  };

  if (anchorId) {
    checkForPartnerSlotConflicts(anchorId, "anchor");
  }
  for (const lock of locks) {
    if (lock.garmentId) {
      checkForPartnerSlotConflicts(lock.garmentId, "lock");
    }
  }

  // Now check if any lock occupies a claimed partner slot with a DIFFERENT garment
  for (const lock of locks) {
    if (!lock.garmentId) continue;
    const g = index.get(lock.garmentId);
    if (!g) continue;
    
    const lockSlot = (lock.slot ?? g.slot) as Slot;
    const claim = partnerSlotClaims.get(lockSlot);
    
    if (claim && claim.partnerId !== lock.garmentId) {
      // This lock occupies a partner's slot with a different garment
      const setMember = index.get(claim.setMemberId);
      const partner = index.get(claim.partnerId);
      const setMemberName = pieceLabel(setMember, claim.setMemberId);
      const partnerName = pieceLabel(partner, claim.partnerId);
      const lockName = pieceLabel(g, lock.garmentId);
      
      const isAnchorConflict = claim.setMemberId === anchorId;
      
      return problem(
        "SET_CONFLICT",
        `SET_CONFLICT: locked ${lockName} occupies ${lockSlot}, the slot of ${partnerName} which is keepTogether with ${isAnchorConflict ? "anchor" : "locked"} ${setMemberName} (D-30, D-32).`,
        [
          {
            garmentId: claim.setMemberId,
            role: isAnchorConflict ? "anchor" : "lock",
            slot: setMember?.slot ?? lockSlot,
            reason: `${setMemberName} requires keepTogether partner ${partnerName} in ${lockSlot}`,
          },
          {
            garmentId: lock.garmentId,
            role: "lock",
            slot: lockSlot,
            reason: `${lockName} cannot be locked in ${lockSlot}; slot claimed by set partner ${partnerName}`,
          },
          {
            garmentId: claim.partnerId,
            role: "missing_partner",
            slot: lockSlot,
            reason: `${partnerName} slot ${lockSlot} is claimed by keepTogether requirement`,
          },
        ],
      );
    }
  }

  // Set integrity for anchor and locks
  const fixedIds: { id: string; role: string; slot: Slot }[] = [];
  if (anchor) {
    fixedIds.push({ id: anchor.id, role: "anchor", slot: anchor.slot });
  }
  for (const lock of locks) {
    if (!lock.garmentId) continue;
    const g = index.get(lock.garmentId);
    if (!g) continue;
    fixedIds.push({
      id: g.id,
      role: "lock",
      slot: (lock.slot ?? g.slot) as Slot,
    });
  }

  for (const fixed of fixedIds) {
    const partners = partnerIdsFor(fixed.id, wardrobe, membersBySet);
    if (partners.length === 0) continue;
    // Only enforce if this garment is keepTogether
    const self = index.get(fixed.id)!;
    const inKeepTogether =
      self.keepTogether === true ||
      [...membersBySet.values()].some(
        (m) => m.includes(fixed.id) && m.length > 1,
      );
    if (!inKeepTogether && !self.keepTogether) continue;

    const fixedName = pieceLabel(self, fixed.id);

    for (const pid of partners) {
      const partner = index.get(pid);
      if (!partner) {
        return problem(
          "SET_CONFLICT",
          `SET_CONFLICT: keepTogether partner ${pid} absent from wardrobe for ${fixed.role} ${fixedName} (D-30).`,
          [
            {
              garmentId: fixed.id,
              role: fixed.role,
              slot: fixed.slot,
              reason: `${fixedName} requires keepTogether partner missing from wardrobe`,
            },
            {
              garmentId: pid,
              role: "missing_partner",
              reason: `Set partner ${pid} is absent from wardrobe`,
            },
          ],
        );
      }
      if (!passesNeverRelax(partner, rules, occasion)) {
        const partnerName = pieceLabel(partner, partner.id);
        return problem(
          "SET_CONFLICT",
          `SET_CONFLICT: keepTogether partner ${partnerName} fails never-relax filters for ${fixed.role} (D-30).`,
          [
            {
              garmentId: fixed.id,
              role: fixed.role,
              slot: fixed.slot,
              reason: `${fixedName} requires keepTogether partner ${partnerName}`,
            },
            {
              garmentId: partner.id,
              role: "missing_partner",
              availability: partner.availability,
              reason: neverRelaxConflictReason(partner, partner.id),
            },
          ],
        );
      }
    }
  }

  return null;
}

/**
 * Map AlternativesRequest → Stage1 swap-mode input (fixed O, open = swap slot).
 */

import type {
  GarmentSummary,
  OutfitAssignment,
  Slot,
  Stage1Input,
  ContextSnapshot,
  StyleProfilePayload,
  GarmentSet,
} from "../types.js";

/** Minimal fields needed to build O / Stage1 swap input. */
export interface SwapRequestSlice {
  slot: Slot;
  currentAssignments: OutfitAssignment[];
  wardrobe: GarmentSummary[];
  context: ContextSnapshot;
  profile?: StyleProfilePayload | null;
  sets?: GarmentSet[];
  limit?: number | null;
  accessoryPolicy?: "OPEN" | "LOCKED";
  options?: { accessoryPolicy?: "OPEN" | "LOCKED" };
}

export interface FixedMap {
  /** slot → garmentId for every filled non-swap assignment */
  O: Map<Slot, string>;
  O_ids: Set<string>;
  O_garments: GarmentSummary[];
  anchorSlot: Slot | null;
  anchorId: string | null;
  lockedSlots: Set<Slot>;
  currentInSlotId: string | null;
  /** ACCESSORY garment IDs when slot is ACCESSORY (D-32: up to 3) */
  accessoryIds: string[];
}

/**
 * Build fixed pieces O from currentAssignments (exclude request.slot).
 */
export function buildFixedMap(
  req: Pick<SwapRequestSlice, "slot" | "currentAssignments" | "wardrobe">,
): FixedMap | { error: "GARMENT_NOT_READY"; detail: string } {
  const wardrobeById = new Map(req.wardrobe.map((g) => [g.id, g]));
  const O = new Map<Slot, string>();
  const O_ids = new Set<string>();
  const lockedSlots = new Set<Slot>();
  let anchorSlot: Slot | null = null;
  let anchorId: string | null = null;
  let currentInSlotId: string | null = null;
  const accessoryIds: string[] = [];

  for (const a of req.currentAssignments) {
    if (a.isLocked) lockedSlots.add(a.slot);
    if (a.isAnchor) {
      anchorSlot = a.slot;
      if (a.garmentId) anchorId = a.garmentId;
    }
    // D-32 #30-2: When swapping ACCESSORY, keep all current accessories as fixed
    // (they share one slot but are distinct items; alternatives must not include siblings)
    const isSwapSlot = a.slot === req.slot;
    const isAccessorySwap = req.slot === "ACCESSORY";
    
    if (isSwapSlot && !isAccessorySwap) {
      // Non-ACCESSORY swap: skip the item being replaced
      if (a.garmentId && a.gapReason == null) currentInSlotId = a.garmentId;
      continue;
    }
    
    if (isSwapSlot && isAccessorySwap) {
      // ACCESSORY swap: track current but DON'T skip - we need all accessories as fixed
      if (a.garmentId && a.gapReason == null) {
        currentInSlotId = a.garmentId;
      }
      // Fall through to add to accessoryIds below
    }
    
    if (a.garmentId == null || a.gapReason != null) continue;
    const g = wardrobeById.get(a.garmentId);
    if (!g) {
      return {
        error: "GARMENT_NOT_READY",
        detail: `Fixed garment ${a.garmentId} for slot ${a.slot} is missing from wardrobe.`,
      };
    }
    // D-32: ACCESSORY can have multiple items (up to 3 of distinct categories)
    if (a.slot === "ACCESSORY") {
      accessoryIds.push(a.garmentId);
      O_ids.add(a.garmentId);
    } else {
      O.set(a.slot, a.garmentId);
      O_ids.add(a.garmentId);
    }
  }

  if (anchorId && !wardrobeById.has(anchorId)) {
    return {
      error: "GARMENT_NOT_READY",
      detail: `Anchor garment ${anchorId} is missing from wardrobe.`,
    };
  }

  const O_garments: GarmentSummary[] = [];
  for (const id of O_ids) {
    const g = wardrobeById.get(id);
    if (g) O_garments.push(g);
  }

  return {
    O,
    O_ids,
    O_garments,
    anchorSlot,
    anchorId,
    lockedSlots,
    currentInSlotId,
    accessoryIds,
  };
}

export function resolveAccessoryPolicy(
  req: SwapRequestSlice,
): "OPEN" | "LOCKED" {
  return req.options?.accessoryPolicy ?? req.accessoryPolicy ?? "OPEN";
}

/**
 * Stage1 input for swap: O as locks (+ anchor), requireSlots = [slot] only.
 */
export function toStage1SwapInput(
  req: SwapRequestSlice,
  fixed: FixedMap,
): Stage1Input {
  // Anchor is fixed via anchorGarmentId — do not also list it as a lock
  // (Stage1 precheck LOCK_CONFLICT if same id is both anchor and lock).
  const lockedAssignments: OutfitAssignment[] = [];
  for (const [slot, garmentId] of fixed.O) {
    if (fixed.anchorId && garmentId === fixed.anchorId) continue;
    lockedAssignments.push({
      slot,
      garmentId,
      isLocked: true,
      isAnchor: false,
    });
  }
  // D-32: Add all ACCESSORY locks (up to 3 of distinct categories)
  for (const garmentId of fixed.accessoryIds) {
    if (fixed.anchorId && garmentId === fixed.anchorId) continue;
    lockedAssignments.push({
      slot: "ACCESSORY",
      garmentId,
      isLocked: true,
      isAnchor: false,
    });
  }

  const accessoryPolicy = resolveAccessoryPolicy(req);
  const limit = clampLimit(req.limit);

  return {
    wardrobe: req.wardrobe,
    context: req.context,
    profile: req.profile ?? null,
    anchorGarmentId: fixed.anchorId,
    lockedAssignments,
    options: {
      requireSlots: [req.slot],
      accessoryPolicy,
      candidatesPerSlot: limit,
    },
    sets: req.sets,
  };
}

export function clampLimit(limit?: number | null): number {
  if (limit == null || Number.isNaN(Number(limit))) return 8;
  return Math.min(12, Math.max(1, Math.floor(Number(limit))));
}

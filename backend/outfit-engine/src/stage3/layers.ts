import type {
  BuilderConfig,
  ContextSnapshot,
  Slot,
  Stage2Options,
  TemperatureBand,
} from "../types.js";
import { DEFAULT_REQUIRE_SLOTS } from "../types.js";

const LAYER_SLOTS: Slot[] = ["MID_LAYER", "JACKET", "OUTERWEAR"];

/**
 * Band → extra required slots (design §4.3).
 * `filled` is the seeded outfit map (fixed only at call time).
 */
export function layerRequirements(
  band: TemperatureBand,
  filled: Map<Slot, string>,
  options?: Stage2Options | null,
): Slot[] {
  void options;

  switch (band) {
    case "COLD":
      // OUTERWEAR required even if JACKET already fixed (T2-08)
      return filled.has("OUTERWEAR") ? [] : ["OUTERWEAR"];
    case "COOL": {
      const hasLayer = LAYER_SLOTS.some((s) => filled.has(s));
      if (hasLayer) return [];
      // Deferred: resolveRequired picks the single best fillable layer slot
      return [];
    }
    case "MILD":
    case "WARM":
    case "HOT":
    default:
      return [];
  }
}

/**
 * Merge base requireSlots ∪ layer requirements, minus already filled.
 * COOL: pick single best layer slot later in runBuilder once shortlists known —
 * caller uses resolveCoolLayerSlot.
 */
export function resolveRequiredSlots(
  context: ContextSnapshot,
  filled: Map<Slot, string>,
  options?: Stage2Options | null,
): Set<Slot> {
  const base = options?.requireSlots ?? DEFAULT_REQUIRE_SLOTS;
  const layer = layerRequirements(context.temperatureBand, filled, options);
  const required = new Set<Slot>([...base, ...layer]);
  for (const s of filled.keys()) required.delete(s);
  return required;
}

/**
 * COOL: among MID_LAYER / JACKET / OUTERWEAR, pick the slot whose top
 * shortlist candidate ranks highest by (score desc, garmentId asc).
 * If all empty → MID_LAYER (first in fill order among the three).
 */
export function resolveCoolLayerSlot(
  shortlistTops: Partial<
    Record<Slot, { garmentId: string; score: number } | null>
  >,
): Slot {
  let best: { slot: Slot; score: number; garmentId: string } | null = null;
  for (const slot of LAYER_SLOTS) {
    const top = shortlistTops[slot];
    if (!top) continue;
    if (
      !best ||
      top.score > best.score ||
      (top.score === best.score && top.garmentId < best.garmentId)
    ) {
      best = { slot, score: top.score, garmentId: top.garmentId };
    }
  }
  return best?.slot ?? "MID_LAYER";
}

/**
 * Whether the builder should attempt to fill an open non-required slot.
 */
export function shouldFillOptional(
  slot: Slot,
  band: TemperatureBand,
  config: BuilderConfig,
  accessoryPolicy: "OPEN" | "LOCKED" | undefined,
  precipitation?: boolean,
): boolean {
  if (slot === "ACCESSORY") {
    if (accessoryPolicy === "LOCKED") return false;
    return config.fillOptionalAccessories;
  }
  if (slot === "OUTERWEAR") {
    // Never optional — only via required (COLD / requireSlots / rain flag)
    if (precipitation && (band === "MILD" || band === "COOL")) return true;
    return false;
  }
  if (slot === "MID_LAYER") {
    // T2-08 expects mid-layer on COLD; keep MILD snapshots free of optional mid
    return band === "COLD";
  }
  if (slot === "JACKET") {
    // WARM/HOT: only if required elsewhere; MILD/COOL/COLD: fill from shortlist
    return band === "MILD" || band === "COOL" || band === "COLD";
  }
  return false;
}

export { LAYER_SLOTS };

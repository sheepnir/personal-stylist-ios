import {
  ALL_SEASONS,
  BAND_SEASONS,
  WARMTH_TOLERANCE,
  type ContextSnapshot,
  type Formality,
  type GarmentSummary,
  type PreferenceRule,
  type Season,
  type TemperatureBand,
  type Warmth,
} from "../types.js";

export interface FilterTier {
  /** Formality half-window: 1 = ±1, 2 = ±2 */
  formalityDelta: 1 | 2;
  /** Extra warmth steps beyond base table (0 or 1). */
  warmthWiden: 0 | 1;
}

export const TIER0: FilterTier = { formalityDelta: 1, warmthWiden: 0 };
export const TIER_FORMALITY: FilterTier = { formalityDelta: 2, warmthWiden: 0 };
export const TIER_WARMTH: FilterTier = { formalityDelta: 2, warmthWiden: 1 };

export function isOwned(g: GarmentSummary): boolean {
  if (g.isWishlist === true) return false;
  if (g.owned === false) return false;
  return true;
}

export function isReady(g: GarmentSummary): boolean {
  if (g.readiness === "DRAFT") return false;
  if (g.readiness === "READY") return true;
  // Derive readiness from required fields (D-23) when readiness omitted.
  return (
    g.slot != null &&
    g.colorPrimary != null &&
    g.pattern != null &&
    g.surface != null &&
    g.formality != null &&
    g.warmth != null
  );
}

export function isAvailable(g: GarmentSummary): boolean {
  const a = g.availability ?? "AVAILABLE";
  return a === "AVAILABLE";
}

export function isArchived(g: GarmentSummary): boolean {
  return g.archivedAt != null && g.archivedAt !== "";
}

export function isAllSeason(seasons: Season[] | undefined): boolean {
  if (!seasons || seasons.length === 0) return false;
  const set = new Set(seasons);
  return ALL_SEASONS.every((s) => set.has(s));
}

export function passesSeason(
  g: GarmentSummary,
  band: TemperatureBand,
): boolean {
  const seasons = (g.seasons ?? []) as Season[];
  if (isAllSeason(seasons)) return true;
  if (seasons.length === 0) return false;
  const implied = new Set(BAND_SEASONS[band]);
  return seasons.some((s) => implied.has(s));
}

export function warmthRange(
  band: TemperatureBand,
  widen: 0 | 1,
): [number, number] {
  const [lo, hi] = WARMTH_TOLERANCE[band];
  if (widen === 0) return [lo, hi];
  return [Math.max(1, lo - 1), Math.min(5, hi + 1)];
}

export function passesWarmth(
  g: GarmentSummary,
  band: TemperatureBand,
  widen: 0 | 1,
): boolean {
  if (g.warmth == null) return false;
  const [lo, hi] = warmthRange(band, widen);
  return g.warmth >= lo && g.warmth <= hi;
}

export function passesFormality(
  g: GarmentSummary,
  occasionFormality: number,
  delta: 1 | 2,
): boolean {
  if (g.formality == null) return false;
  const lo = occasionFormality - delta;
  const hi = occasionFormality + delta;
  return g.formality >= lo && g.formality <= hi;
}

/** Map occasion → rule scopes that apply. ALWAYS always applies. */
export function scopesForOccasion(occasion: string): Set<string> {
  const scopes = new Set<string>(["ALWAYS"]);
  const o = occasion.toUpperCase();
  if (o.includes("WORK") || o.includes("CLIENT") || o.includes("EXEC")) {
    scopes.add("WORK");
  }
  if (o.includes("WEEKEND") || o.includes("CASUAL") || o.includes("ERRAND")) {
    scopes.add("WEEKEND");
  }
  if (o.includes("EVENING") || o.includes("SPECIAL")) {
    scopes.add("EVENING");
  }
  if (o.includes("TRAVEL")) {
    scopes.add("TRAVEL");
  }
  return scopes;
}

function isCombinationSubject(subject: Record<string, unknown>): boolean {
  return (
    subject.pair != null ||
    subject.garmentIds != null ||
    subject.color_families != null ||
    subject.colorFamilies != null
  );
}

/**
 * Single-garment DISLIKE / AVOID_HARD only (D-26: combination pairs skipped).
 */
export function violatesSingleGarmentRule(
  g: GarmentSummary,
  rules: PreferenceRule[],
  occasion: string,
): boolean {
  const scopes = scopesForOccasion(occasion);
  for (const rule of rules) {
    if (rule.active === false) continue;
    if (rule.polarity !== "DISLIKE" && rule.polarity !== "AVOID_HARD") continue;
    if (!scopes.has(String(rule.scope).toUpperCase())) continue;
    const subject = rule.subject ?? {};
    if (rule.kind === "COMBINATION" || isCombinationSubject(subject)) {
      continue; // D-26 deferred
    }
    if (subject.garmentId != null && subject.garmentId === g.id) return true;
    if (
      typeof subject.color_family === "string" &&
      g.colorPrimary?.family === subject.color_family
    ) {
      return true;
    }
    if (
      typeof subject.colorFamily === "string" &&
      g.colorPrimary?.family === subject.colorFamily
    ) {
      return true;
    }
    if (
      typeof subject.pattern === "string" &&
      g.pattern === subject.pattern
    ) {
      return true;
    }
    if (
      typeof subject.material === "string" &&
      (g.materials ?? []).includes(subject.material)
    ) {
      return true;
    }
    if (
      typeof subject.category === "string" &&
      g.category === subject.category
    ) {
      return true;
    }
  }
  return false;
}

/** Never-relax filters (D-23, D-25). Used by prechecks for anchor/locks/set partners. */
export function passesNeverRelax(
  g: GarmentSummary,
  rules: PreferenceRule[],
  occasion: string,
): boolean {
  if (!isAvailable(g)) return false;
  if (!isReady(g)) return false;
  if (isArchived(g)) return false;
  if (!isOwned(g)) return false;
  if (violatesSingleGarmentRule(g, rules, occasion)) return false;
  return true;
}

/**
 * Full Stage 1 filters at a given relaxation tier (excludes set atomicity).
 */
export function passesFiltersAtTier(
  g: GarmentSummary,
  context: ContextSnapshot,
  rules: PreferenceRule[],
  tier: FilterTier,
): boolean {
  if (!passesNeverRelax(g, rules, context.occasion)) return false;
  if (!passesSeason(g, context.temperatureBand)) return false;
  if (!passesWarmth(g, context.temperatureBand, tier.warmthWiden)) return false;
  if (
    !passesFormality(
      g,
      context.occasionFormality as Formality,
      tier.formalityDelta,
    )
  ) {
    return false;
  }
  return true;
}

import { effectiveScore } from "./sets.js";
import type {
  Boldness,
  GarmentSummary,
  ScoreBreakdown,
  ScoredCandidate,
  ScoringConfig,
  Slot,
  Stage2Options,
} from "../types.js";

export function resolveCap(
  boldness: Boldness,
  options: Stage2Options | undefined,
  config: ScoringConfig,
): number {
  const { minCap, maxCap, defaultCap, boldnessCaps } = config.shortlist;
  let base: number;
  const explicitCap = options?.candidatesPerSlot;
  
  if (explicitCap != null) {
    // Explicit request wins as pre-boldness base
    base = Math.min(Math.max(1, explicitCap), maxCap);
  } else {
    base = Math.min(Math.max(defaultCap, minCap), maxCap);
  }

  switch (boldness) {
    case "FAMILIAR":
      return Math.min(base, boldnessCaps.FAMILIAR);
    case "SLIGHT_STRETCH":
      return Math.min(base, boldnessCaps.SLIGHT_STRETCH);
    case "BOLD":
      // When explicit cap is set, treat it as a ceiling (issue #38)
      if (explicitCap != null) {
        return Math.min(base, maxCap);
      }
      return Math.min(Math.max(base, boldnessCaps.BOLD), maxCap);
    default:
      return base;
  }
}

function rankGarments(
  garments: GarmentSummary[],
  scores: Record<string, ScoreBreakdown>,
  setScores: Map<string, number>,
): GarmentSummary[] {
  return [...garments].sort((a, b) => {
    const sa = effectiveScore(a, scores, setScores);
    const sb = effectiveScore(b, scores, setScores);
    if (sb !== sa) return sb - sa;
    return a.id.localeCompare(b.id);
  });
}

export interface ShortlistBuildResult {
  shortlist: Partial<Record<Slot, ScoredCandidate[]>>;
  colourDiversityExpansions: { slot: Slot; garmentId: string }[];
}

/**
 * Rank, take top cap (excluding force-weak ids from under-cap), colour diversity,
 * optional BOLD stretch inject. Set over-cap expansion is applied separately.
 * 
 * Issue #38: Colour-family coverage is now bounded by maxCap + 2 and skipped for FAMILIAR.
 */
export function buildSlotShortlists(
  eligibleAfterCombo: Partial<Record<Slot, GarmentSummary[]>>,
  scores: Record<string, ScoreBreakdown>,
  setScores: Map<string, number>,
  cap: number,
  boldness: Boldness,
  config: ScoringConfig,
  fixedPieces: GarmentSummary[],
  options: Stage2Options | undefined,
  setWithById: Map<string, string[]>,
): ShortlistBuildResult {
  const forceWeak = options?.force_weak_bottom_score_for;
  const colourDiversityExpansions: { slot: Slot; garmentId: string }[] = [];
  const shortlist: Partial<Record<Slot, ScoredCandidate[]>> = {};

  for (const [slot, garments] of Object.entries(eligibleAfterCombo) as [
    Slot,
    GarmentSummary[],
  ][]) {
    if (!garments || garments.length === 0) {
      shortlist[slot] = [];
      continue;
    }

    const ranked = rankGarments(garments, scores, setScores);
    const underCap: GarmentSummary[] = [];
    for (const g of ranked) {
      if (forceWeak && g.id === forceWeak) continue;
      underCap.push(g);
      if (underCap.length >= cap) break;
    }

    const selected = new Map<string, ScoredCandidate>();
    const toCandidate = (
      g: GarmentSummary,
      overCapReason?: ScoredCandidate["overCapReason"],
    ): ScoredCandidate => ({
      garmentId: g.id,
      slot,
      score: effectiveScore(g, scores, setScores),
      breakdown: scores[g.id]!,
      setId: g.setId ?? null,
      setWith: setWithById.get(g.id),
      ...(overCapReason ? { overCapReason } : {}),
    });

    for (const g of underCap) {
      selected.set(g.id, toCandidate(g));
    }

    if (config.shortlist.ensureColourFamilyCoverage && boldness !== "FAMILIAR") {
      // Issue #38: Skip coverage for FAMILIAR; bound total shortlist by maxCap + 2
      const maxShortlistSize = config.shortlist.maxCap + 2;
      
      const families = new Map<string, GarmentSummary>();
      for (const g of ranked) {
        const fam = g.colorPrimary?.family?.toLowerCase();
        if (!fam) continue;
        if (!families.has(fam)) families.set(fam, g);
      }
      for (const [, bestOfFamily] of families) {
        if (selected.size >= maxShortlistSize) break; // Hard ceiling
        if (selected.has(bestOfFamily.id)) continue;
        if (forceWeak && bestOfFamily.id === forceWeak) continue;
        selected.set(
          bestOfFamily.id,
          toCandidate(bestOfFamily, "COLOUR_DIVERSITY"),
        );
        colourDiversityExpansions.push({
          slot,
          garmentId: bestOfFamily.id,
        });
      }
    }

    if (boldness === "BOLD") {
      const avoidFamilies = new Set(
        fixedPieces
          .map((p) => p.colorPrimary?.family?.toLowerCase())
          .filter((x): x is string => !!x),
      );
      const ordered = [...selected.values()];
      const topId = ordered[0]?.garmentId;
      const topFam = topId
        ? garments
            .find((g) => g.id === topId)
            ?.colorPrimary?.family?.toLowerCase()
        : null;
      if (topFam) avoidFamilies.add(topFam);

      for (const g of ranked) {
        if (selected.has(g.id)) continue;
        if (forceWeak && g.id === forceWeak) continue;
        const fam = g.colorPrimary?.family?.toLowerCase();
        if (fam && avoidFamilies.has(fam)) continue;
        selected.set(g.id, toCandidate(g, "BOLD_STRETCH"));
        break;
      }
    }

    const underIds = new Set(underCap.map((g) => g.id));
    const orderedOut: ScoredCandidate[] = [];
    for (const g of ranked) {
      const c = selected.get(g.id);
      if (c && underIds.has(g.id) && !c.overCapReason) orderedOut.push(c);
    }
    for (const g of ranked) {
      const c = selected.get(g.id);
      if (c && c.overCapReason) orderedOut.push(c);
    }
    for (const c of selected.values()) {
      if (!orderedOut.includes(c)) orderedOut.push(c);
    }

    shortlist[slot] = orderedOut;
  }

  return { shortlist, colourDiversityExpansions };
}

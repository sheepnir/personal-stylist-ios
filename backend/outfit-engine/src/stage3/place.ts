import { buildKeepTogetherMembership } from "../shared/membership.js";
import { scoreGarment, type ScoreContext } from "../stage2/score.js";
import type {
  BuilderSkippedMeta,
  ContextSnapshot,
  GarmentSet,
  GarmentSummary,
  PreferenceRule,
  ScoredCandidate,
  ScoringConfig,
  Slot,
  Stage2History,
  Stage2Result,
} from "../types.js";
import { completesForbiddenPair } from "./combination.js";
import { DEFAULT_FILL_ORDER } from "./config.js";

export type OutfitMap = Map<Slot, string>;

export interface PlaceContext {
  stage2: Stage2Result;
  wardrobeById: Map<string, GarmentSummary>;
  sets: GarmentSet[] | undefined;
  membersBySet: Map<string, string[]>;
  rules: PreferenceRule[];
  outfit: OutfitMap;
  outfitIds: Set<string>;
  skipped: BuilderSkippedMeta[];
  rescoreContext?: {
    context: ContextSnapshot;
    history?: Stage2History | null;
    asOfDate: string;
    config: ScoringConfig;
  } | null;
}

export function buildPlaceContext(
  stage2: Stage2Result,
  wardrobe: GarmentSummary[],
  sets: GarmentSet[] | undefined,
  rules: PreferenceRule[],
  outfit: OutfitMap,
  rescoreContext?: {
    context: ContextSnapshot;
    history?: Stage2History | null;
    asOfDate: string;
    config: ScoringConfig;
  } | null,
): PlaceContext {
  const wardrobeById = new Map(wardrobe.map((g) => [g.id, g]));
  const membersBySet = buildKeepTogetherMembership(wardrobe, sets);
  return {
    stage2,
    wardrobeById,
    sets,
    membersBySet,
    rules,
    outfit,
    outfitIds: new Set(outfit.values()),
    skipped: [],
    rescoreContext,
  };
}

function outfitGarments(ctx: PlaceContext): GarmentSummary[] {
  const out: GarmentSummary[] = [];
  for (const id of ctx.outfitIds) {
    const g = ctx.wardrobeById.get(id);
    if (g) out.push(g);
  }
  return out;
}

function setIdFor(g: GarmentSummary, ctx: PlaceContext): string | null {
  if (g.setId) {
    const members = ctx.membersBySet.get(g.setId);
    if (members && members.length > 1) return g.setId;
  }
  for (const [setId, members] of ctx.membersBySet) {
    if (members.includes(g.id) && members.length > 1) return setId;
  }
  return null;
}

function isKeepTogetherMember(g: GarmentSummary, ctx: PlaceContext): boolean {
  return setIdFor(g, ctx) != null;
}

type SetPlan =
  | { kind: "IMPOSSIBLE" }
  | {
      kind: "OK";
      placements: { slot: Slot; garmentId: string; source: "shortlist" | "set_partner" }[];
    };

/**
 * Plan atomic keepTogether placement for candidate c at its slot.
 */
export function planSetPlacement(
  c: ScoredCandidate,
  ctx: PlaceContext,
): SetPlan {
  const garment = ctx.wardrobeById.get(c.garmentId);
  if (!garment) return { kind: "IMPOSSIBLE" };
  const setId = setIdFor(garment, ctx);
  if (!setId) {
    return {
      kind: "OK",
      placements: [{ slot: c.slot, garmentId: c.garmentId, source: "shortlist" }],
    };
  }
  const members = ctx.membersBySet.get(setId) ?? [];
  const placements: {
    slot: Slot;
    garmentId: string;
    source: "shortlist" | "set_partner";
  }[] = [];

  // Simulate on a copy
  const simOutfit = new Map(ctx.outfit);
  const simIds = new Set(ctx.outfitIds);

  for (const mid of members) {
    const mg = ctx.wardrobeById.get(mid);
    if (!mg) return { kind: "IMPOSSIBLE" };
    const occupied = simOutfit.get(mg.slot);
    if (occupied != null) {
      if (occupied === mid) continue; // already correctly placed
      return { kind: "IMPOSSIBLE" }; // slot taken by different garment
    }
    // Open slot — member must be in shortlist (or be the candidate we're placing)
    const list = ctx.stage2.shortlist[mg.slot] ?? [];
    const inShortlist = list.some((x) => x.garmentId === mid);
    if (!inShortlist && mid !== c.garmentId) {
      return { kind: "IMPOSSIBLE" };
    }
    // Combo-check vs current sim outfit
    if (
      completesForbiddenPair(mg, simIds, garmentsFromIds(simIds, ctx), ctx.rules)
    ) {
      return { kind: "IMPOSSIBLE" };
    }
    placements.push({
      slot: mg.slot,
      garmentId: mid,
      source: mid === c.garmentId ? "shortlist" : "set_partner",
    });
    simOutfit.set(mg.slot, mid);
    simIds.add(mid);
  }

  // Order placements by FILL_ORDER for stable apply
  placements.sort(
    (a, b) =>
      DEFAULT_FILL_ORDER.indexOf(a.slot) - DEFAULT_FILL_ORDER.indexOf(b.slot),
  );

  return { kind: "OK", placements };
}

function garmentsFromIds(
  ids: Set<string>,
  ctx: PlaceContext,
): GarmentSummary[] {
  const out: GarmentSummary[] = [];
  for (const id of ids) {
    const g = ctx.wardrobeById.get(id);
    if (g) out.push(g);
  }
  return out;
}

export interface TryPlaceResult {
  placed: boolean;
  placements: {
    slot: Slot;
    garmentId: string;
    source: "shortlist" | "set_partner";
  }[];
}

/**
 * Re-score a single candidate against the current outfit pieces.
 * Returns the re-scored total or null if rescoring is not configured.
 */
function rescoreCandidate(
  candidate: ScoredCandidate,
  ctx: PlaceContext,
): number | null {
  if (!ctx.rescoreContext) return null;
  
  const g = ctx.wardrobeById.get(candidate.garmentId);
  if (!g) return null;
  
  const fixedPieces = outfitGarments(ctx);
  const scoreCtx: ScoreContext = {
    fixedPieces,
    context: ctx.rescoreContext.context,
    history: ctx.rescoreContext.history,
    asOfDate: ctx.rescoreContext.asOfDate,
    config: ctx.rescoreContext.config,
  };
  
  const breakdown = scoreGarment(g, scoreCtx);
  return breakdown.total;
}

/**
 * Greedy place for open slot s — first shortlist candidate that survives
 * combo + set checks (design §4.5–4.6).
 * 
 * When rescoreContext is provided (D-41), re-scores remaining candidates
 * against pieces placed so far before selecting.
 */
export function tryPlace(slot: Slot, ctx: PlaceContext, pseudoAnchorId?: string | null): TryPlaceResult {
  let candidates = ctx.stage2.shortlist[slot] ?? [];
  
  // D-41: Re-score remaining shortlist against pieces placed so far
  // For no-anchor cases, pieces placed includes the pseudo-anchor
  const hasPiecesForScoring = ctx.outfitIds.size > 0 || pseudoAnchorId != null;
  if (ctx.rescoreContext && candidates.length > 0 && hasPiecesForScoring) {
    // Temporarily add pseudo-anchor to outfit for scoring if applicable
    const origOutfitIds = pseudoAnchorId ? new Set(ctx.outfitIds) : null;
    if (pseudoAnchorId && !ctx.outfitIds.has(pseudoAnchorId)) {
      ctx.outfitIds.add(pseudoAnchorId);
    }
    
    const rescored: Array<ScoredCandidate & { rescore: number }> = [];
    for (const c of candidates) {
      const newScore = rescoreCandidate(c, ctx);
      if (newScore !== null) {
        rescored.push({ ...c, rescore: newScore });
      } else {
        rescored.push({ ...c, rescore: c.score });
      }
    }
    // Sort by rescore desc, then garmentId asc for stable tie-break
    rescored.sort((a, b) => {
      if (b.rescore !== a.rescore) return b.rescore - a.rescore;
      return a.garmentId.localeCompare(b.garmentId);
    });
    candidates = rescored;
    
    // Restore original outfitIds if we added pseudo-anchor temporarily
    if (origOutfitIds && pseudoAnchorId) {
      ctx.outfitIds = origOutfitIds;
    }
  }
  
  for (const c of candidates) {
    if (ctx.outfitIds.has(c.garmentId)) {
      ctx.skipped.push({
        slot,
        garmentId: c.garmentId,
        reason: "ALREADY_USED",
      });
      continue;
    }
    const g = ctx.wardrobeById.get(c.garmentId);
    if (!g) continue;

    if (
      completesForbiddenPair(g, ctx.outfitIds, outfitGarments(ctx), ctx.rules)
    ) {
      ctx.skipped.push({
        slot,
        garmentId: c.garmentId,
        reason: "COMBINATION",
      });
      continue;
    }

    if (isKeepTogetherMember(g, ctx)) {
      const plan = planSetPlacement(c, ctx);
      if (plan.kind === "IMPOSSIBLE") {
        ctx.skipped.push({
          slot,
          garmentId: c.garmentId,
          reason: "SET_INCOMPLETE",
        });
        continue;
      }
      // Apply atomically
      for (const p of plan.placements) {
        ctx.outfit.set(p.slot, p.garmentId);
        ctx.outfitIds.add(p.garmentId);
      }
      return { placed: true, placements: plan.placements };
    }

    ctx.outfit.set(slot, c.garmentId);
    ctx.outfitIds.add(c.garmentId);
    return {
      placed: true,
      placements: [{ slot, garmentId: c.garmentId, source: "shortlist" }],
    };
  }
  return { placed: false, placements: [] };
}

/**
 * Place up to maxAccessories from ACCESSORY shortlist, skipping combo +
 * duplicate category.
 */
export function tryPlaceAccessories(
  ctx: PlaceContext,
  maxAccessories: number,
): {
  slot: Slot;
  garmentId: string;
  source: "shortlist";
}[] {
  const placed: { slot: Slot; garmentId: string; source: "shortlist" }[] = [];
  const categories = new Set<string>();
  // Collect categories already fixed
  for (const id of ctx.outfitIds) {
    const g = ctx.wardrobeById.get(id);
    if (g?.slot === "ACCESSORY" && g.category) {
      categories.add(String(g.category).toUpperCase());
    }
  }

  const candidates = ctx.stage2.shortlist.ACCESSORY ?? [];
  for (const c of candidates) {
    if (placed.length >= maxAccessories) break;
    if (ctx.outfitIds.has(c.garmentId)) {
      ctx.skipped.push({
        slot: "ACCESSORY",
        garmentId: c.garmentId,
        reason: "ALREADY_USED",
      });
      continue;
    }
    const g = ctx.wardrobeById.get(c.garmentId);
    if (!g) continue;
    const cat = g.category ? String(g.category).toUpperCase() : null;
    if (cat && categories.has(cat)) continue;
    if (
      completesForbiddenPair(g, ctx.outfitIds, outfitGarments(ctx), ctx.rules)
    ) {
      ctx.skipped.push({
        slot: "ACCESSORY",
        garmentId: c.garmentId,
        reason: "COMBINATION",
      });
      continue;
    }
    // Accessories share slot ACCESSORY — store multiple via parallel list;
    // outfit map can only hold one; use a synthetic approach: track in placed
    // and outfitIds only (not overwriting single Map slot for multi-accessory).
    ctx.outfitIds.add(c.garmentId);
    if (cat) categories.add(cat);
    placed.push({ slot: "ACCESSORY", garmentId: c.garmentId, source: "shortlist" });
  }
  return placed;
}

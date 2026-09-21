/**
 * M0-21 · POST /v1/outfit/alternatives — deterministic swap ranking.
 * Stage1 filter + Stage2 score for ONE slot vs fixed pieces O.
 * Zero network / zero OpenRouter.
 */

import { runStage1 } from "../stage1/hardFilter.js";
import { passesNeverRelax, isReady, isAvailable, isOwned, isArchived } from "../stage1/filters.js";
import { partnerIdsFor } from "../stage1/prechecks.js";
import { buildKeepTogetherMembership } from "../shared/membership.js";
import { applyCombinationExclusion } from "../stage2/combination.js";
import { scoreGarment } from "../stage2/score.js";
import { resolveScoringConfig } from "../stage2/config.js";
import {
  computeSetScores,
  effectiveScore,
} from "../stage2/sets.js";
import { completesForbiddenPair, activeCombinationRules } from "../stage3/combination.js";
import type {
  ContextSnapshot,
  GarmentSet,
  GarmentSummary,
  OutfitAssignment,
  PreferenceRule,
  ScoreBreakdown,
  Slot,
  StyleProfilePayload,
} from "../types.js";
import { ALL_SLOTS } from "../types.js";
import type { LocalProblemBody } from "../pipeline/generateLocal.js";
import { templateReason } from "./reasonTemplate.js";
import {
  buildFixedMap,
  clampLimit,
  resolveAccessoryPolicy,
  toStage1SwapInput,
  type FixedMap,
} from "./toStage1SwapInput.js";

export type EmptyReason =
  | "NO_ELIGIBLE"
  | "SET_BLOCKED"
  | "COMBINATION_BLOCKED"
  | "LOCK_FIXED";

export interface AlternativesRequest {
  slot: Slot;
  currentAssignments: OutfitAssignment[];
  wardrobe: GarmentSummary[];
  profile?: StyleProfilePayload | null;
  context: ContextSnapshot;
  recentOutfits?: string[][];
  limit?: number;
  requestId?: string | null;
  /** Proposed; accepted on local bridge until OpenAPI adds it. */
  accessoryPolicy?: "OPEN" | "LOCKED";
  options?: {
    accessoryPolicy?: "OPEN" | "LOCKED";
  };
  sets?: GarmentSet[];
  /** Ignored — always recompute (D-33 / design §5.1). */
  candidateSet?: unknown;
  asOfDate?: string;
}

export interface AlternativeRow {
  garmentId: string;
  score: number;
  reason: string;
  setPartnerIds?: string[];
}

export interface AlternativesResponse {
  slot: Slot;
  alternatives: AlternativeRow[];
  emptyReason?: EmptyReason | null;
}

export type RankAlternativesOutput = AlternativesResponse | LocalProblemBody;

export function isAlternativesProblem(
  out: RankAlternativesOutput,
): out is LocalProblemBody {
  return (
    typeof out === "object" &&
    out !== null &&
    "status" in out &&
    (out as LocalProblemBody).status === 400 &&
    "code" in out
  );
}

function problem(
  code: string,
  title: string,
  detail: string,
): LocalProblemBody {
  return {
    type: "about:blank",
    title,
    status: 400,
    detail,
    code,
    dataPreserved: true,
  };
}

function empty(
  slot: Slot,
  emptyReason: EmptyReason,
): AlternativesResponse {
  return { slot, alternatives: [], emptyReason };
}

function isValidSlot(slot: unknown): slot is Slot {
  return typeof slot === "string" && (ALL_SLOTS as string[]).includes(slot);
}

/**
 * keepTogether partners not already correctly placed in O that would move
 * if the user picks g. Empty if partner slot locked to a stranger / partner
 * fails never-relax / partner missing → candidate illegal (null).
 */
function resolveSetPartners(
  g: GarmentSummary,
  fixed: FixedMap,
  wardrobe: GarmentSummary[],
  membersBySet: Map<string, string[]>,
  rules: PreferenceRule[],
  occasion: string,
): string[] | null {
  const partners = partnerIdsFor(g.id, wardrobe, membersBySet);
  if (partners.length === 0) return [];

  const wardrobeById = new Map(wardrobe.map((x) => [x.id, x]));
  const setPartnerIds: string[] = [];

  for (const pid of partners) {
    const p = wardrobeById.get(pid);
    if (!p) return null;
    // Never-relax on partner
    if (
      !isOwned(p) ||
      isArchived(p) ||
      !isReady(p) ||
      !isAvailable(p) ||
      !passesNeverRelax(p, rules, occasion)
    ) {
      return null;
    }

    const occupiedInO = fixed.O.get(p.slot);
    if (occupiedInO != null) {
      if (occupiedInO === pid) continue; // already correctly placed
      // Slot taken by stranger — cannot pull set
      return null;
    }
    // Partner slot empty in O — must not be locked to something else
    // (empty + locked is unusual; if lockedSlots has the slot with no O entry, still blocked)
    if (fixed.lockedSlots.has(p.slot)) return null;

    setPartnerIds.push(pid);
  }

  return setPartnerIds;
}

/**
 * Resolve asOfDate to a local calendar date (YYYY-MM-DD).
 * Falls back to context.capturedAt or wall clock if not provided.
 */
function asOfDateFor(req: AlternativesRequest): string {
  let dateStr: string;
  
  if (req.asOfDate) {
    dateStr = req.asOfDate;
  } else if (req.context.capturedAt) {
    dateStr = req.context.capturedAt;
  } else {
    // Wall-clock fallback: extract local calendar date
    dateStr = new Date().toISOString();
  }

  // Extract YYYY-MM-DD portion for consistent calendar date handling
  return dateStr.includes("T") ? dateStr.split("T")[0] : dateStr;
}

/**
 * Rank alternative garments for a single swap slot against fixed pieces O.
 */
export function rankAlternatives(
  req: AlternativesRequest,
): RankAlternativesOutput {
  if (!req || !Array.isArray(req.wardrobe) || req.wardrobe.length < 1) {
    return problem(
      "INVALID_REQUEST",
      "Invalid request",
      "Request must include a non-empty wardrobe.",
    );
  }
  if (!req.context) {
    return problem(
      "INVALID_REQUEST",
      "Invalid request",
      "Request must include context.",
    );
  }
  if (!isValidSlot(req.slot)) {
    return problem(
      "INVALID_REQUEST",
      "Invalid request",
      `slot must be one of ${ALL_SLOTS.join(", ")}.`,
    );
  }
  if (
    !Array.isArray(req.currentAssignments) ||
    req.currentAssignments.length < 1
  ) {
    return problem(
      "INVALID_REQUEST",
      "Invalid request",
      "currentAssignments must be a non-empty array.",
    );
  }

  const fixedOrErr = buildFixedMap(req);
  if ("error" in fixedOrErr) {
    return problem(
      fixedOrErr.error,
      "Garment not ready",
      fixedOrErr.detail,
    );
  }
  const fixed = fixedOrErr;

  // LOCK_FIXED: swap slot locked or is the anchor (200 + emptyReason)
  const slotAssignment = req.currentAssignments.find((a) => a.slot === req.slot);
  const slotLocked = slotAssignment?.isLocked === true || fixed.lockedSlots.has(req.slot);
  const slotIsAnchor =
    slotAssignment?.isAnchor === true || fixed.anchorSlot === req.slot;

  const accessoryPolicy = resolveAccessoryPolicy(req);
  if (accessoryPolicy === "LOCKED" && req.slot === "ACCESSORY") {
    return empty(req.slot, "LOCK_FIXED");
  }
  if (slotLocked || slotIsAnchor) {
    return empty(req.slot, "LOCK_FIXED");
  }

  // Issue #32: Check if outgoing garment is part of a keepTogether set with partners in O
  const membersBySet = buildKeepTogetherMembership(req.wardrobe, req.sets);
  if (fixed.currentInSlotId) {
    const outgoingPartners = partnerIdsFor(
      fixed.currentInSlotId,
      req.wardrobe,
      membersBySet,
    );
    if (outgoingPartners.length > 0) {
      // Check if any partner is in O (the fixed pieces)
      const partnersInO = outgoingPartners.filter((pid) => fixed.O_ids.has(pid));
      if (partnersInO.length > 0) {
        // Swapping would leave the set half-used (D-30, D-22)
        return empty(req.slot, "SET_BLOCKED");
      }
    }
  }

  const stage1Input = toStage1SwapInput(req, fixed);
  const stage1 = runStage1(stage1Input);
  if (!stage1.ok) {
    return {
      type: "about:blank",
      title: stage1.title,
      status: 400,
      detail: stage1.detail,
      code: stage1.code,
      ...(stage1.conflicts ? { conflicts: stage1.conflicts } : {}),
      dataPreserved: true,
    };
  }

  const rules: PreferenceRule[] = req.profile?.activeRules ?? [];
  const wardrobeById = new Map(req.wardrobe.map((g) => [g.id, g]));

  // Stage1 candidates for slot, minus current-in-slot and already-in-O
  let stage1Eligible = (stage1.eligibleGarments[req.slot] ?? []).filter(
    (g) =>
      g.id !== fixed.currentInSlotId &&
      !fixed.O_ids.has(g.id) &&
      !stage1.fixed.some((f) => f.garmentId === g.id),
  );

  // Track set-blocked vs genuinely no eligible
  let setBlockedCount = 0;
  const afterSetIntegrity: GarmentSummary[] = [];
  for (const g of stage1Eligible) {
    const partners = resolveSetPartners(
      g,
      fixed,
      req.wardrobe,
      membersBySet,
      rules,
      req.context.occasion,
    );
    if (partners == null) {
      setBlockedCount++;
      continue;
    }
    afterSetIntegrity.push(g);
  }

  // Also: same-slot garments that Stage1 dropped solely via set atomicity
  // (for emptyReason when afterSetIntegrity is empty and stage1Eligible empty)
  const sameSlotReady = req.wardrobe.filter((g) => {
    if (g.slot !== req.slot) return false;
    if (g.id === fixed.currentInSlotId) return false;
    if (fixed.O_ids.has(g.id)) return false;
    return (
      isOwned(g) &&
      !isArchived(g) &&
      isReady(g) &&
      isAvailable(g) &&
      passesNeverRelax(g, rules, req.context.occasion)
    );
  });

  if (afterSetIntegrity.length === 0) {
    if (stage1Eligible.length === 0 && sameSlotReady.length > 0) {
      // Likely set atomicity in Stage1 removed keepTogether candidates
      const anyKeepTogether = sameSlotReady.some((g) => {
        const partners = partnerIdsFor(g.id, req.wardrobe, membersBySet);
        return partners.length > 0;
      });
      if (anyKeepTogether) return empty(req.slot, "SET_BLOCKED");
      return empty(req.slot, "NO_ELIGIBLE");
    }
    if (setBlockedCount > 0) return empty(req.slot, "SET_BLOCKED");
    return empty(req.slot, "NO_ELIGIBLE");
  }

  // Combination exclusion vs O
  const fixedSlots = new Set(fixed.O.keys());
  const eligibleMap: Partial<Record<Slot, GarmentSummary[]>> = {
    [req.slot]: afterSetIntegrity,
  };
  const { eligibleAfterCombo, excludedByCombination } =
    applyCombinationExclusion(
      eligibleMap,
      fixed.O_garments,
      fixed.O_ids,
      fixedSlots,
      rules,
      req.context,
    );

  let survivors = eligibleAfterCombo[req.slot] ?? [];

  // Also drop via completesForbiddenPair (shared Stage3 helper) for parity
  const activeRules = activeCombinationRules(rules, req.context.occasion);
  survivors = survivors.filter(
    (g) =>
      !completesForbiddenPair(g, fixed.O_ids, fixed.O_garments, activeRules),
  );

  if (survivors.length === 0) {
    if (
      excludedByCombination.length > 0 ||
      afterSetIntegrity.length > 0
    ) {
      // Had stage1/set survivors but all combo-clashed
      return empty(req.slot, "COMBINATION_BLOCKED");
    }
    return empty(req.slot, "NO_ELIGIBLE");
  }

  const config = resolveScoringConfig();
  const asOfDate = asOfDateFor(req);
  const history =
    req.recentOutfits && req.recentOutfits.length > 0
      ? {
          suggestions: req.recentOutfits.map((garmentIds) => ({
            suggestedAt: asOfDate,
            garmentIds,
          })),
        }
      : null;

  const scores: Record<string, ScoreBreakdown> = {};
  for (const g of survivors) {
    scores[g.id] = scoreGarment(g, {
      fixedPieces: fixed.O_garments,
      context: req.context,
      history,
      asOfDate,
      config,
    });
  }

  // Score set partners that would move (for setMinScore)
  for (const g of survivors) {
    const partners = resolveSetPartners(
      g,
      fixed,
      req.wardrobe,
      membersBySet,
      rules,
      req.context.occasion,
    );
    if (!partners) continue;
    for (const pid of partners) {
      if (scores[pid]) continue;
      const p = wardrobeById.get(pid);
      if (!p) continue;
      scores[pid] = scoreGarment(p, {
        fixedPieces: fixed.O_garments,
        context: req.context,
        history,
        asOfDate,
        config,
      });
    }
  }

  const candidateIds = new Set(Object.keys(scores));
  const setScores = computeSetScores(
    membersBySet,
    candidateIds,
    fixed.O_ids,
    scores,
  );

  const currentInSlot = fixed.currentInSlotId
    ? wardrobeById.get(fixed.currentInSlotId) ?? null
    : null;

  type Ranked = {
    g: GarmentSummary;
    score: number;
    breakdown: ScoreBreakdown;
    setPartnerIds: string[];
  };

  const ranked: Ranked[] = [];
  for (const g of survivors) {
    const partners =
      resolveSetPartners(
        g,
        fixed,
        req.wardrobe,
        membersBySet,
        rules,
        req.context.occasion,
      ) ?? [];
    const score = effectiveScore(g, scores, setScores);
    ranked.push({
      g,
      score,
      breakdown: scores[g.id]!,
      setPartnerIds: partners,
    });
  }

  ranked.sort((a, b) => {
    if (b.score !== a.score) return b.score - a.score;
    return a.g.id.localeCompare(b.g.id);
  });

  const limit = clampLimit(req.limit);
  const sliced = ranked.slice(0, limit);

  const alternatives: AlternativeRow[] = sliced.map((r) => {
    const row: AlternativeRow = {
      garmentId: r.g.id,
      score: r.score,
      reason: templateReason(
        r.breakdown,
        fixed.O_garments,
        r.g,
        req.context,
        currentInSlot,
      ),
    };
    if (r.setPartnerIds.length > 0) {
      row.setPartnerIds = r.setPartnerIds;
    }
    return row;
  });

  return {
    slot: req.slot,
    alternatives,
    emptyReason: null,
  };
}

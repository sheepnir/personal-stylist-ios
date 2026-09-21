import { resolveScoringConfig } from "./config.js";
import { applyCombinationExclusion } from "./combination.js";
import { scoreGarment } from "./score.js";
import {
  buildKeepTogetherMembership,
  computeSetScores,
  expandSetShortlist,
} from "./sets.js";
import { buildSlotShortlists, resolveCap } from "./shortlist.js";
import type {
  Boldness,
  GarmentSummary,
  PreferenceRule,
  ScoreBreakdown,
  ScoringConfig,
  Slot,
  Stage1Result,
  Stage2Input,
  Stage2Result,
} from "../types.js";
import { DEFAULT_REQUIRE_SLOTS } from "../types.js";

/**
 * Resolve asOfDate to a local calendar date (YYYY-MM-DD).
 * Falls back to context.capturedAt or wall clock if not provided.
 * 
 * @returns tuple of [resolvedDate, wasProvidedExplicitly]
 */
function resolveAsOfDate(input: Stage2Input): [string, boolean] {
  let dateStr: string;
  let wasProvided = false;

  if (input.asOfDate) {
    dateStr = input.asOfDate;
    wasProvided = true;
  } else if (input.context.capturedAt) {
    dateStr = input.context.capturedAt;
  } else {
    // Wall-clock fallback: extract local calendar date
    dateStr = new Date().toISOString();
  }

  // Extract YYYY-MM-DD portion for consistent calendar date handling
  const datePart = dateStr.includes("T") ? dateStr.split("T")[0] : dateStr;
  
  return [datePart, wasProvided];
}

function resolveFixedPieces(
  fixed: Stage1Result["fixed"],
  wardrobeById: Map<string, GarmentSummary>,
): GarmentSummary[] {
  const out: GarmentSummary[] = [];
  for (const f of fixed) {
    const g = wardrobeById.get(f.garmentId);
    if (g) out.push(g);
  }
  return out;
}

/**
 * Stage 2: combination exclusion vs fixed, score, set unit scores,
 * shortlist with caps / diversity / set over-cap. Pure, no network.
 */
export function runStage2(
  stage1: Stage1Result,
  input: Stage2Input,
  configOverride?: Partial<ScoringConfig> | null,
): Stage2Result {
  if (!stage1.ok) {
    throw new Error("runStage2 requires stage1.ok === true");
  }

  // Issue #38: Validate candidatesPerSlot against OpenAPI range [4, 10]
  if (input.options?.candidatesPerSlot != null) {
    const cap = input.options.candidatesPerSlot;
    if (cap < 4 || cap > 10) {
      throw new Error(
        `candidatesPerSlot must be in range [4, 10], got ${cap}`,
      );
    }
  }

  const config = resolveScoringConfig(configOverride);
  const boldness: Boldness = input.boldness ?? "SLIGHT_STRETCH";
  const [asOfDate, asOfDateProvided] = resolveAsOfDate(input);
  const wardrobeById = new Map(input.wardrobe.map((g) => [g.id, g]));
  const fixedPieces = resolveFixedPieces(stage1.fixed, wardrobeById);
  const fixedIds = new Set(stage1.fixed.map((f) => f.garmentId));
  const fixedSlots = new Set(stage1.fixed.map((f) => f.slot));

  const rules: PreferenceRule[] = input.profile?.activeRules ?? [];

  const { eligibleAfterCombo, excludedByCombination } =
    applyCombinationExclusion(
      stage1.eligibleGarments,
      fixedPieces,
      fixedIds,
      fixedSlots,
      rules,
      input.context,
    );

  if (input.options?.accessoryPolicy === "LOCKED") {
    eligibleAfterCombo.ACCESSORY = [];
  }

  const forceWeakId = input.options?.force_weak_bottom_score_for;
  const scores: Record<string, ScoreBreakdown> = {};
  for (const garments of Object.values(eligibleAfterCombo)) {
    for (const g of garments ?? []) {
      if (scores[g.id]) continue;
      scores[g.id] = scoreGarment(g, {
        fixedPieces,
        context: input.context,
        history: input.history,
        asOfDate,
        config,
        forceTotal: forceWeakId && g.id === forceWeakId ? -1000 : undefined,
      });
    }
  }

  const membersBySet = buildKeepTogetherMembership(input.wardrobe, input.sets);
  const candidateIds = new Set(Object.keys(scores));
  const setScores = computeSetScores(
    membersBySet,
    candidateIds,
    fixedIds,
    scores,
  );

  const setWithById = new Map<string, string[]>();
  for (const [, members] of membersBySet) {
    if (members.length < 2) continue;
    for (const mid of members) {
      setWithById.set(
        mid,
        members.filter((x) => x !== mid),
      );
    }
  }

  const cap = resolveCap(boldness, input.options, config);
  const { shortlist, colourDiversityExpansions } = buildSlotShortlists(
    eligibleAfterCombo,
    scores,
    setScores,
    cap,
    boldness,
    config,
    fixedPieces,
    input.options,
    setWithById,
  );

  const { expansions } = expandSetShortlist(
    shortlist,
    membersBySet,
    wardrobeById,
    eligibleAfterCombo,
    fixedIds,
    scores,
    setScores,
  );

  const requireSlots = input.options?.requireSlots ?? DEFAULT_REQUIRE_SLOTS;
  const gaps = new Set<Slot>(stage1.gaps);
  for (const slot of requireSlots) {
    if (fixedSlots.has(slot)) continue;
    const list = eligibleAfterCombo[slot] ?? [];
    if (list.length === 0) gaps.add(slot);
  }

  for (const slot of fixedSlots) {
    if (slot === "ACCESSORY") continue;
    shortlist[slot] = [];
  }

  const candidateIdsOut: Partial<Record<Slot, string[]>> = {};
  for (const [slot, list] of Object.entries(shortlist) as [
    Slot,
    (typeof shortlist)[Slot],
  ][]) {
    candidateIdsOut[slot] = (list ?? []).map((c) => c.garmentId);
  }

  return {
    ok: true,
    shortlist,
    candidateIds: candidateIdsOut,
    scores,
    excludedByCombination,
    setShortlistExpansions: expansions,
    colourDiversityExpansions:
      colourDiversityExpansions.length > 0
        ? colourDiversityExpansions
        : undefined,
    fixed: stage1.fixed,
    gaps: [...gaps],
    relaxationsApplied: stage1.relaxationsApplied,
    meta: {
      capUsed: cap,
      boldness,
      weightsVersion: config.weightsVersion,
      asOfDateProvided: asOfDateProvided || undefined,
    },
  };
}

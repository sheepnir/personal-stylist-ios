import type {
  GarmentSummary,
  ScoreBreakdown,
  ScoredCandidate,
  Slot,
} from "../types.js";

export { buildKeepTogetherMembership } from "../shared/membership.js";

/**
 * setScore = min(member totals) among free candidates.
 * Hybrid (any member fixed): no unit setScore — free members use own totals.
 */
export function computeSetScores(
  membersBySet: Map<string, string[]>,
  candidateIds: Set<string>,
  fixedIds: Set<string>,
  scores: Record<string, ScoreBreakdown>,
): Map<string, number> {
  const setScores = new Map<string, number>();

  for (const [setId, members] of membersBySet) {
    if (members.length < 2) continue;
    const free = members.filter((id) => candidateIds.has(id));
    if (free.length === 0) continue;
    const anyFixed = members.some((id) => fixedIds.has(id));
    if (anyFixed) continue;
    const totals = free
      .map((id) => scores[id]?.total)
      .filter((t): t is number => t != null);
    if (totals.length === 0) continue;
    setScores.set(setId, Math.min(...totals));
  }

  return setScores;
}

export function effectiveScore(
  g: GarmentSummary,
  scores: Record<string, ScoreBreakdown>,
  setScores: Map<string, number>,
): number {
  if (g.setId && setScores.has(g.setId)) {
    return setScores.get(g.setId)!;
  }
  return scores[g.id]?.total ?? 0;
}

/**
 * If any free member is in shortlist, append every other free eligible partner
 * even over the cap (D-30). Returns expansion audit + mutates shortlist in place.
 */
export function expandSetShortlist(
  shortlist: Partial<Record<Slot, ScoredCandidate[]>>,
  membersBySet: Map<string, string[]>,
  wardrobeById: Map<string, GarmentSummary>,
  eligibleAfterCombo: Partial<Record<Slot, GarmentSummary[]>>,
  fixedIds: Set<string>,
  scores: Record<string, ScoreBreakdown>,
  setScores: Map<string, number>,
): {
  expansions: {
    setId: string;
    pulledOverCap: { slot: Slot; garmentId: string }[];
  }[];
} {
  const expansions: {
    setId: string;
    pulledOverCap: { slot: Slot; garmentId: string }[];
  }[] = [];

  const shortlistedIds = new Set<string>();
  for (const list of Object.values(shortlist)) {
    for (const c of list ?? []) shortlistedIds.add(c.garmentId);
  }

  const eligibleIds = new Set<string>();
  for (const list of Object.values(eligibleAfterCombo)) {
    for (const g of list ?? []) eligibleIds.add(g.id);
  }

  for (const [setId, members] of membersBySet) {
    if (members.length < 2) continue;

    const anyInShortlist = members.some(
      (id) => shortlistedIds.has(id) && !fixedIds.has(id),
    );
    if (!anyInShortlist) continue;

    const pulled: { slot: Slot; garmentId: string }[] = [];
    for (const pid of members) {
      if (fixedIds.has(pid)) continue;
      if (shortlistedIds.has(pid)) continue;
      if (!eligibleIds.has(pid)) continue;
      const garment = wardrobeById.get(pid);
      if (!garment || !scores[pid]) continue;
      const slot = garment.slot;
      const list = shortlist[slot] ?? [];
      list.push({
        garmentId: pid,
        slot,
        score: effectiveScore(garment, scores, setScores),
        breakdown: scores[pid],
        setId: garment.setId ?? setId,
        setWith: members.filter((x) => x !== pid),
        overCapReason: "SET_PARTNER",
      });
      shortlist[slot] = list;
      shortlistedIds.add(pid);
      pulled.push({ slot, garmentId: pid });
    }
    if (pulled.length > 0) {
      expansions.push({ setId, pulledOverCap: pulled });
    }
  }

  return { expansions };
}

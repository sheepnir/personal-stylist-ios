import type { OutfitAssignment } from "../types.js";

function filledGarmentIds(assignments: OutfitAssignment[]): string[] {
  return assignments
    .filter((a) => a.garmentId)
    .map((a) => a.garmentId!)
    .sort();
}

function sameIdSet(a: string[], b: string[]): boolean {
  if (a.length !== b.length) return false;
  const sa = [...a].sort();
  const sb = [...b].sort();
  return sa.every((id, i) => id === sb[i]);
}

/**
 * True when the outfit matches any excluded garment-id set (try-another parity).
 */
export function matchesExcludedGarmentSet(
  assignments: OutfitAssignment[],
  excludeGarmentSets: string[][] | null | undefined,
): boolean {
  if (!excludeGarmentSets?.length) return false;
  const filled = filledGarmentIds(assignments);
  return excludeGarmentSets.some((ex) => sameIdSet(ex, filled));
}

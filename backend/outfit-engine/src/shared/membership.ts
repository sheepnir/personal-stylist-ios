import type { GarmentSet, GarmentSummary } from "../types.js";

/**
 * Build keepTogether set membership map.
 *
 * A set is established when:
 * - It appears in the `sets` catalog with `keepTogether: true`, OR
 * - Any garment with that `setId` has `keepTogether: true`
 *
 * Once established, ALL garments sharing that `setId` are members,
 * regardless of their individual `keepTogether` flag.
 *
 * This unified logic replaces the divergent implementations in:
 * - `buildSetMembership` (stage1/prechecks.ts)
 * - `buildKeepTogetherSets` (stage2/sets.ts)
 *
 * @param wardrobe - All garments
 * @param sets - Optional sets catalog
 * @returns Map from setId to array of member garment IDs
 */
export function buildKeepTogetherMembership(
  wardrobe: GarmentSummary[],
  sets: GarmentSet[] | undefined,
): Map<string, string[]> {
  const membersBySet = new Map<string, string[]>();

  // Pass 1: Add sets from catalog where keepTogether is true
  for (const s of sets ?? []) {
    if (!s.keepTogether) continue;
    membersBySet.set(s.id, [...s.memberGarmentIds]);
  }

  // Pass 2: Add garments with keepTogether=true and a setId
  for (const g of wardrobe) {
    if (!g.keepTogether || !g.setId) continue;
    const existing = membersBySet.get(g.setId) ?? [];
    if (!existing.includes(g.id)) existing.push(g.id);
    membersBySet.set(g.setId, existing);
  }

  // Pass 3: Add ALL garments that share a setId with an established set
  // (Partners referenced only via another member's setId)
  for (const g of wardrobe) {
    if (!g.setId) continue;
    const existing = membersBySet.get(g.setId);
    if (!existing) continue;
    if (!existing.includes(g.id)) {
      existing.push(g.id);
      membersBySet.set(g.setId, existing);
    }
  }

  return membersBySet;
}

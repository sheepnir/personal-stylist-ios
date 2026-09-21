import type { OutfitAssignment, Slot } from "../types.js";
import { DEFAULT_FILL_ORDER } from "./config.js";

/** Sort assignments into FILL_ORDER with gap rows inline at their slot position. */
export function sortAssignmentsInline(
  assignments: OutfitAssignment[],
  fillOrder: Slot[] = DEFAULT_FILL_ORDER,
): OutfitAssignment[] {
  const orderIndex = new Map(fillOrder.map((s, i) => [s, i]));
  const accessoryRows: OutfitAssignment[] = [];
  const bySlot = new Map<Slot, OutfitAssignment>();

  for (const a of assignments) {
    if (a.slot === "ACCESSORY") {
      accessoryRows.push(a);
      continue;
    }
    bySlot.set(a.slot, a);
  }

  const out: OutfitAssignment[] = [];
  for (const slot of fillOrder) {
    if (slot === "ACCESSORY") {
      out.push(...accessoryRows);
      continue;
    }
    const row = bySlot.get(slot);
    if (row) out.push(row);
  }

  // Any unexpected slots not in fillOrder — append stably by slot name
  for (const a of assignments) {
    if (a.slot === "ACCESSORY") continue;
    if (!orderIndex.has(a.slot) && !out.includes(a)) {
      out.push(a);
    }
  }

  return out;
}

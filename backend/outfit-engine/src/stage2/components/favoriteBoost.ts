import type { GarmentSummary } from "../../types.js";

export function favoriteBoost(g: GarmentSummary): number {
  return g.isFavorite ? 1 : 0;
}

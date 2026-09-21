/**
 * Deterministic one-line reasons for swap alternatives (≤120 chars).
 * Templated from Stage 2 score components — never model-generated.
 */

import { WARMTH_TOLERANCE } from "../types.js";
import type {
  ContextSnapshot,
  GarmentSummary,
  ScoreBreakdown,
} from "../types.js";

const MAX_LEN = 120;

function joinFragments(parts: string[]): string {
  const join = (items: string[]) => items.length < 3
    ? items.join(" and ")
    : `${items.slice(0, -1).join(", ")}, and ${items.at(-1)}`;
  const accepted: string[] = [];
  for (const part of parts) {
    // Drop whole fragments instead of cutting a sentence in the middle of a name.
    if (join([...accepted, part]).length + 1 <= MAX_LEN) accepted.push(part);
  }
  return `${join(accepted) || "works with the pieces you’re keeping"}.`;
}

function colourName(g: GarmentSummary): string {
  return (g.colorPrimary?.name?.trim() || g.colorPrimary?.family || "")
    .replaceAll("_", " ");
}

function colourPairFragment(
  g: GarmentSummary,
  fixed: GarmentSummary[],
): string | null {
  const gf = g.colorPrimary?.family?.toLowerCase();
  if (!gf) return null;
  for (const o of fixed) {
    const of = o.colorPrimary?.family?.toLowerCase();
    if (!of || of === gf) continue;
    // Prefer a non-identical pairing mention when colourHarmony is strong
    return `pairs ${colourName(g)} with ${colourName(o)}`;
  }
  return null;
}

function weatherFragment(
  g: GarmentSummary,
  context: ContextSnapshot,
  current?: GarmentSummary | null,
): string | null {
  if (g.warmth == null) return null;
  const [lo, hi] = WARMTH_TOLERANCE[context.temperatureBand];
  const mid = (lo + hi) / 2;
  if (current?.warmth != null) {
    if (g.warmth < current.warmth) return "feels cooler than the current piece";
    if (g.warmth > current.warmth) return "feels warmer than the current piece";
  }
  // Absolute fit vs band centre
  if (Math.abs(g.warmth - mid) <= 0.5) {
    return `suits ${context.temperatureBand.toLowerCase()} weather`;
  }
  if (g.warmth < mid) return "adds a lighter layer";
  if (g.warmth > mid) return "adds warmth";
  return null;
}

/**
 * Build a ≤120-char templated reason from Stage 2 breakdown + fixed pieces.
 */
export function templateReason(
  breakdown: ScoreBreakdown,
  fixedPieces: GarmentSummary[],
  g: GarmentSummary,
  context: ContextSnapshot,
  currentInSlot?: GarmentSummary | null,
): string {
  const c = breakdown.components;
  const parts: string[] = [];

  if ((c.colorHarmony ?? 0) >= 0.8) {
    const frag = colourPairFragment(g, fixedPieces);
    if (frag) parts.push(frag);
  }

  if ((c.weatherFit ?? 0) >= 0.7) {
    const frag = weatherFragment(g, context, currentInSlot);
    if (frag) parts.push(frag);
  }

  if ((c.textureContrast ?? 0) >= 0.85) {
    parts.push("adds texture contrast");
  }

  if ((c.formalityCoherence ?? 0) >= 0.85) {
    parts.push("suits the formality of the outfit");
  }

  if ((c.neglectBoost ?? 0) >= 0.5) {
    const name = (g.displayName ?? "piece").trim();
    const short =
      name.length > 28 ? name.slice(0, 27).trimEnd() + "…" : name;
    parts.push(`gives the ${short} a wear`);
  }

  return joinFragments(parts);
}

import defaultsJson from "../../config/scoring.defaults.json";
import type { ScoringConfig, ScoringWeights } from "../types.js";

export const DEFAULT_SCORING_CONFIG: ScoringConfig =
  defaultsJson as ScoringConfig;

/** Deep-merge override onto defaults (weights + nested knobs). */
export function resolveScoringConfig(
  override?: Partial<ScoringConfig> | null,
): ScoringConfig {
  if (!override) {
    return structuredClone(DEFAULT_SCORING_CONFIG);
  }
  const base = structuredClone(DEFAULT_SCORING_CONFIG);
  return {
    ...base,
    ...override,
    weights: { ...base.weights, ...(override.weights ?? {}) },
    shortlist: { ...base.shortlist, ...(override.shortlist ?? {}) },
    neglect: { ...base.neglect, ...(override.neglect ?? {}) },
    recency: { ...base.recency, ...(override.recency ?? {}) },
    repeatPair: { ...base.repeatPair, ...(override.repeatPair ?? {}) },
    color: {
      ...base.color,
      ...(override.color ?? {}),
      neutrals: override.color?.neutrals ?? base.color.neutrals,
      analogousGroups:
        override.color?.analogousGroups ?? base.color.analogousGroups,
      complementaryPairs:
        override.color?.complementaryPairs ?? base.color.complementaryPairs,
    },
    formality: { ...base.formality, ...(override.formality ?? {}) },
    clampTotal:
      override.clampTotal !== undefined
        ? override.clampTotal
        : base.clampTotal,
  };
}

/** Inject alternate weights for tests without editing component functions. */
export function withWeights(
  weights: Partial<ScoringWeights>,
  base?: ScoringConfig,
): ScoringConfig {
  const cfg = resolveScoringConfig(base ?? null);
  return { ...cfg, weights: { ...cfg.weights, ...weights } };
}

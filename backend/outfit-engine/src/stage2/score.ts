import { colorHarmony } from "./components/colorHarmony.js";
import { favoriteBoost } from "./components/favoriteBoost.js";
import { formalityCoherence } from "./components/formalityCoherence.js";
import { neglectBoost } from "./components/neglectBoost.js";
import { recencyPenalty } from "./components/recencyPenalty.js";
import { repeatPairPenalty } from "./components/repeatPairPenalty.js";
import { textureContrast } from "./components/textureContrast.js";
import { weatherFit } from "./components/weatherFit.js";
import type {
  ContextSnapshot,
  GarmentSummary,
  ScoreBreakdown,
  ScoringConfig,
  Stage2History,
} from "../types.js";

export interface ScoreContext {
  fixedPieces: GarmentSummary[];
  context: ContextSnapshot;
  history?: Stage2History | null;
  asOfDate: string;
  config: ScoringConfig;
  /** Test-only absolute total override (e.g. force_weak). */
  forceTotal?: number;
}

/**
 * Compute component scores + weighted total from ScoringConfig weights.
 * Price / cost-per-wear must never appear here (D-01).
 */
export function scoreGarment(
  g: GarmentSummary,
  ctx: ScoreContext,
): ScoreBreakdown {
  const { config, fixedPieces, context, history, asOfDate } = ctx;

  const components: Record<string, number> = {
    colorHarmony: colorHarmony(g, fixedPieces, config),
    textureContrast: textureContrast(g, fixedPieces),
    formalityCoherence: formalityCoherence(g, fixedPieces, context, config),
    neglectBoost: neglectBoost(g, asOfDate, config),
    favoriteBoost: favoriteBoost(g),
    weatherFit: weatherFit(g, context),
    recencyPenalty: recencyPenalty(g, asOfDate, history, config),
    repeatPairPenalty: repeatPairPenalty(
      g,
      fixedPieces,
      asOfDate,
      history,
      config,
    ),
  };

  const w = config.weights;
  const weighted: Record<string, number> = {
    colorHarmony: w.w_color * components.colorHarmony,
    textureContrast: w.w_texture * components.textureContrast,
    formalityCoherence: w.w_form * components.formalityCoherence,
    neglectBoost: w.w_neglect * components.neglectBoost,
    favoriteBoost: w.w_fav * components.favoriteBoost,
    weatherFit: w.w_weather * components.weatherFit,
    recencyPenalty: -(w.w_recent * components.recencyPenalty),
    repeatPairPenalty: -(w.w_repeat * components.repeatPairPenalty),
  };

  let total = Object.values(weighted).reduce((a, b) => a + b, 0);
  if (ctx.forceTotal != null) {
    total = ctx.forceTotal;
  } else if (config.clampTotal) {
    const [lo, hi] = config.clampTotal;
    total = Math.min(hi, Math.max(lo, total));
  }

  return { components, weighted, total };
}

export { runStage1 } from "./stage1/hardFilter.js";
export {
  passesNeverRelax,
  passesFiltersAtTier,
  TIER0,
  TIER_FORMALITY,
  TIER_WARMTH,
} from "./stage1/filters.js";
export { runPrechecks } from "./stage1/prechecks.js";
export { buildKeepTogetherMembership } from "./shared/membership.js";

export { runStage2 } from "./stage2/runStage2.js";
export {
  DEFAULT_SCORING_CONFIG,
  resolveScoringConfig,
  withWeights,
} from "./stage2/config.js";
export { scoreGarment } from "./stage2/score.js";
export { applyCombinationExclusion } from "./stage2/combination.js";
export { resolveCap } from "./stage2/shortlist.js";

export { runBuilder } from "./stage3/runBuilder.js";
export {
  DEFAULT_BUILDER_CONFIG,
  DEFAULT_FILL_ORDER,
  resolveBuilderConfig,
} from "./stage3/config.js";
export { completesForbiddenPair } from "./stage3/combination.js";

export { runStage4 } from "./stage4/runStage4.js";

export type * from "./types.js";
export {
  DEFAULT_REQUIRE_SLOTS,
  WARMTH_TOLERANCE,
  BAND_SEASONS,
  ALL_SLOTS,
} from "./types.js";

export {
  generateLocal,
  isLocalProblem,
} from "./pipeline/generateLocal.js";
export type {
  LocalGenerateRequest,
  LocalGenerateResponse,
  LocalProblemBody,
  GenerateLocalOutput,
} from "./pipeline/generateLocal.js";

export {
  rankAlternatives,
  isAlternativesProblem,
} from "./alternatives/rankAlternatives.js";
export type {
  AlternativesRequest,
  AlternativesResponse,
  AlternativeRow,
  EmptyReason,
  RankAlternativesOutput,
} from "./alternatives/rankAlternatives.js";
export { templateReason } from "./alternatives/reasonTemplate.js";

export {
  CURRENT_STYLIST_PROMPT,
  CURRENT_STYLIST_PROMPT_VERSION,
  REGISTERED_PROMPT_CONTENT_HASHES,
  STYLIST_PROMPT_MODULES,
  getStylistPromptByVersion,
  resolveRegisteredStylistPrompt,
  assertPromptRegistryIntegrity,
  hashStylistPromptModule,
  buildProviderSuccessGeneration,
  outfitT2D1,
} from "./provider/index.js";
export type {
  StylistPromptModule,
  StylistPromptOptionDescription,
  ProviderSuccessGenerationMeta,
  BuildProviderSuccessGenerationOptions,
} from "./provider/index.js";

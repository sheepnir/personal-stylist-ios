import { CURRENT_STYLIST_PROMPT } from "./registry.js";
import type { StylistPromptModule } from "./promptVersionTypes.js";

export type ProviderFallbackLevel = "NONE" | "DETERMINISTIC";

/** Generation block after a successful provider/mock call (openapi GenerationMeta subset). */
export interface ProviderSuccessGenerationMeta {
  modelId: string;
  promptVersion: string;
  candidateSetHash: string | null;
  latencyMs: number;
  inputTokens: number | null;
  outputTokens: number | null;
  costUSD: number | null;
  repairAttempts: number;
  fallbackLevel: "NONE";
  spendState: "OK" | "SOFT_THRESHOLD";
}

export interface BuildProviderSuccessGenerationOptions {
  candidateSetHash: string | null;
  latencyMs: number;
  modelId?: string;
  prompt?: StylistPromptModule;
  inputTokens?: number | null;
  outputTokens?: number | null;
  costUSD?: number | null;
  spendState?: "OK" | "SOFT_THRESHOLD";
}

/**
 * Builds `generation` metadata for a successful provider path result.
 * Worker sets modelId and candidateSetHash from the attempt (ADR-0001 §8).
 */
export function buildProviderSuccessGeneration(
  options: BuildProviderSuccessGenerationOptions,
): ProviderSuccessGenerationMeta {
  const prompt = options.prompt ?? CURRENT_STYLIST_PROMPT;
  return {
    modelId: options.modelId ?? "mock/stylist-v0",
    promptVersion: prompt.version,
    candidateSetHash: options.candidateSetHash,
    latencyMs: options.latencyMs,
    inputTokens: options.inputTokens ?? null,
    outputTokens: options.outputTokens ?? null,
    costUSD: options.costUSD ?? null,
    repairAttempts: 0,
    fallbackLevel: "NONE",
    spendState: options.spendState ?? "OK",
  };
}

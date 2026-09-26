/**
 * Eval harness types — backlog M0-17 / PRD §10.4 / D-29.
 * Extended for M1-F05-07 multi-step alternatives_swap_rerank.
 */

export type OutcomeClassification =
  | "complete"
  | "gap"
  | "problem"
  | "alternatives"
  | "unknown";

export interface ScenarioEvalResult {
  scenarioId: string;
  title?: string;
  task?: string;
  model: string;
  /** ADR-0001 §8: recorded per eval model arm (`none` for deterministic). */
  promptVersion: string;
  /** Soft pass: classification + must_* / gap / problem_code / alternatives constraints. */
  passed: boolean;
  expectedClassification: OutcomeClassification;
  actualClassification: OutcomeClassification;
  /** Exact slot→id vs expected.complete_outfit; null if N/A. */
  exactOutfitMatch: boolean | null;
  failures: string[];
  actualSummary: {
    problemCode?: string;
    outfit?: Record<string, string | null>;
    gaps?: Record<string, string>;
    /** Multi-step alternatives summaries. */
    step1RankedIds?: string[];
    step2RankedIds?: string[];
    step1EmptyReason?: string | null;
    step2EmptyReason?: string | null;
    aStaleOrderDiffers?: boolean;
  };
  /** Determinism across --repeats; null if repeats === 1. */
  deterministic?: boolean | null;
  repeats?: number;
}

export interface EvalReport {
  models: string[];
  scenarios: string[];
  repeats: number;
  passed: number;
  failed: number;
  deferredModels: string[];
  deferredMessages: string[];
  results: ScenarioEvalResult[];
}

export interface RunEvalOptions {
  models: string[];
  /** Scenario ids / prefixes, "all", or globs (T2-0*). */
  scenarios: string | string[];
  repeats?: number;
  fixturesRoot?: string;
  taskFilter?: (task: string | undefined, id: string) => boolean;
}

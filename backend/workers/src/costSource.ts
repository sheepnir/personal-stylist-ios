/**
 * Provider cost lookup for unknown-outcome reconciliation (#13-b).
 * Phase A uses mocks only; no network.
 */

export type CostLookupOutcome = 'known' | 'unknown' | 'error';

export interface CostLookupResult {
  outcome: CostLookupOutcome;
  /** Present when outcome is `known`. */
  costUSD?: number;
}

export interface CostSource {
  lookup(generationId: string, attemptId: string): CostLookupResult;
}

/** Default in the Durable Object until a live lookup is wired (#14+). */
export const NO_COST_SOURCE: CostSource = {
  lookup: () => ({ outcome: 'unknown' }),
};

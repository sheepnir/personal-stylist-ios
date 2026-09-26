/**
 * Phase A guardrails (ADR-0001 §2): no live OpenRouter calls in any environment.
 */

/** When true, `callOpenRouter` must refuse before any network I/O. */
export const PHASE_A_NO_LIVE_PROVIDER = true;

export class PhaseAProviderBlockedError extends Error {
  constructor(caller: string) {
    super(
      `Phase A forbids live provider calls (${caller}). Use an injected mock StylistProvider in tests.`,
    );
    this.name = "PhaseAProviderBlockedError";
  }
}

export function assertPhaseANoLiveProvider(caller: string): void {
  if (PHASE_A_NO_LIVE_PROVIDER) {
    throw new PhaseAProviderBlockedError(caller);
  }
}

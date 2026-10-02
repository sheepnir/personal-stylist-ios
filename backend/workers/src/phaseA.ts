/**
 * Historical chat-client guardrail (ADR-0001 §2): no live calls through this client.
 * ADR-0003 separately permits the gated typed Decisions path in paidSelection.ts.
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

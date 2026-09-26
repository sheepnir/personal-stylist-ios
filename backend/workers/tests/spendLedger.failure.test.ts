/**
 * Spend ledger failure paths: unknown aging, CostSource retries, no network (#14).
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import type { CostSource } from '../src/costSource.js';
import {
  ageLedger,
  emptyLedgerState,
  markAttemptUnknown,
  reserveAttempt,
  summarizeDay,
  countUnresolvedAttempts,
  COST_LOOKUP_BACKOFF_MS,
  UNKNOWN_OUTCOME_AGING_MS,
} from '../src/ledgerCore.js';

const DAY = '2026-09-26';
const CONFIG = { dailyCapUSD: 1.0, softThresholdUSD: 0.5 };

describe('spendLedger failure paths (ledgerCore)', () => {
  let fetchSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    fetchSpy = vi.spyOn(globalThis, 'fetch').mockRejectedValue(
      new Error('network must not be used in ledger tests')
    );
  });

  afterEach(() => {
    fetchSpy.mockRestore();
  });

  it('markUnknown counts toward reservedUSD and unresolvedAttempts until reconcile', () => {
    const state = emptyLedgerState();
    reserveAttempt(state, 'u1', 0.41, DAY, CONFIG);
    markAttemptUnknown(state, 'u1', 'gen-u1');

    let summary = summarizeDay(state, DAY, CONFIG);
    expect(summary.reservedUSD).toBeCloseTo(0.41);
    expect(summary.unresolvedAttempts).toBe(1);

    const costSource: CostSource = {
      lookup: () => ({ outcome: 'known', costUSD: 0.1 }),
    };
    const base = new Date(`${DAY}T12:00:00.000Z`);
    state.days[DAY]!.attempts.u1.createdAt = new Date(`${DAY}T11:00:00.000Z`).toISOString();
    ageLedger(state, base, costSource);

    summary = summarizeDay(state, DAY, CONFIG);
    expect(summary.spentUSD).toBeCloseTo(0.1);
    expect(summary.reservedUSD).toBeCloseTo(0);
    expect(summary.unresolvedAttempts).toBe(0);
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it('ages unknown to spent at upper bound after 24h with injected clock', () => {
    const state = emptyLedgerState();
    reserveAttempt(state, 'age-1', 0.44, DAY, CONFIG);
    markAttemptUnknown(state, 'age-1', 'gen-age');

    const reservedAt = new Date(`${DAY}T09:00:00.000Z`);
    state.days[DAY]!.attempts['age-1'].createdAt = reservedAt.toISOString();

    const atBoundary = new Date(reservedAt.getTime() + UNKNOWN_OUTCOME_AGING_MS);
    ageLedger(state, atBoundary, { lookup: () => ({ outcome: 'unknown' }) });

    const summary = summarizeDay(state, DAY, CONFIG);
    expect(summary.spentUSD).toBeCloseTo(0.44);
    expect(summary.reservedUSD).toBeCloseTo(0);
    expect(countUnresolvedAttempts(state, DAY)).toBe(0);
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it('retries failed CostSource lookups within backoff and keeps attempt unresolved', () => {
    const state = emptyLedgerState();
    reserveAttempt(state, 'retry-1', 0.3, DAY, CONFIG);
    markAttemptUnknown(state, 'retry-1', 'gen-retry');

    const created = new Date(`${DAY}T10:00:00.000Z`);
    state.days[DAY]!.attempts['retry-1'].createdAt = created.toISOString();

    let lookupCalls = 0;
    const failing: CostSource = {
      lookup: () => {
        lookupCalls += 1;
        return { outcome: 'error' };
      },
    };

    const t0 = new Date(`${DAY}T10:00:01.000Z`);
    ageLedger(state, t0, failing);
    expect(lookupCalls).toBe(1);
    expect(summarizeDay(state, DAY, CONFIG).unresolvedAttempts).toBe(1);
    expect(summarizeDay(state, DAY, CONFIG).reservedUSD).toBeCloseTo(0.3);

    const entry = state.days[DAY]!.attempts['retry-1'];
    expect(entry.costLookupCount).toBe(1);

    const beforeBackoff = new Date(t0.getTime() + COST_LOOKUP_BACKOFF_MS[1]! - 1);
    ageLedger(state, beforeBackoff, failing);
    expect(lookupCalls).toBe(1);

    const afterBackoff = new Date(t0.getTime() + COST_LOOKUP_BACKOFF_MS[1]!);
    ageLedger(state, afterBackoff, failing);
    expect(lookupCalls).toBe(2);
    expect(summarizeDay(state, DAY, CONFIG).unresolvedAttempts).toBe(1);

    const succeeding: CostSource = {
      lookup: () => ({ outcome: 'known', costUSD: 0.11 }),
    };
    const thirdLookup = new Date(afterBackoff.getTime() + COST_LOOKUP_BACKOFF_MS[2]!);
    ageLedger(state, thirdLookup, succeeding);
    const summary = summarizeDay(state, DAY, CONFIG);
    expect(summary.spentUSD).toBeCloseTo(0.11);
    expect(summary.unresolvedAttempts).toBe(0);
    expect(fetchSpy).not.toHaveBeenCalled();
  });
});

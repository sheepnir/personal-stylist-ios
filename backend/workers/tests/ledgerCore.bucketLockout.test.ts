/**
 * Regression tests for bucket-count lockout (QA fix/13a-bucket-limit-lockout).
 */

import { describe, it, expect } from 'vitest';
import {
  countSettledBucketsOutsideEvictionWindow,
  emptyLedgerState,
  pruneOldDays,
  reconcileAttempt,
  reserveAttempt,
  summarizeDay,
  LEDGER_DAY_BUCKETS,
} from '../src/ledgerCore.js';

const DAY = '2026-09-26';
const CONFIG = { dailyCapUSD: 1.0, softThresholdUSD: 0.5 };
const NOW = new Date(`${DAY}T12:00:00.000Z`);

function utcDayKeyMinusDays(day: string, daysBack: number): string {
  const ms = Date.parse(`${day}T00:00:00.000Z`) - daysBack * 86_400_000;
  return new Date(ms).toISOString().split('T')[0];
}

function settledDay(dayKey: string, spentMicro = 1000) {
  return {
    date: dayKey,
    spentMicro,
    reservedMicro: 0,
    overReservationCount: 0,
    attempts: {},
    tasks: Object.create(null),
  };
}

function openDay(dayKey: string, attemptId: string, state: 'reserved' | 'unknown' = 'reserved') {
  const upperBoundMicro = 50_000;
  return {
    date: dayKey,
    spentMicro: 0,
    reservedMicro: upperBoundMicro,
    overReservationCount: 0,
    attempts: {
      [attemptId]: {
        attemptId,
        upperBoundMicro,
        task: 'generate',
        state,
        createdAt: NOW.toISOString(),
      },
    },
    tasks: Object.create(null),
  };
}

function fillProtectedWindowSettled(state: ReturnType<typeof emptyLedgerState>): void {
  for (let age = 0; age <= 30; age += 1) {
    const dayKey = utcDayKeyMinusDays(DAY, age);
    state.days[dayKey] = settledDay(dayKey, age === 0 ? 0 : 1000);
  }
}

describe('bucket limit lockout regressions', () => {
  it('(a) settled tomorrow plus 31 window buckets allows new hold when under money cap', () => {
    const state = emptyLedgerState();
    fillProtectedWindowSettled(state);
    const tomorrow = utcDayKeyMinusDays(DAY, -1);
    state.days[tomorrow] = settledDay(tomorrow, 500);
    expect(Object.keys(state.days).length).toBe(LEDGER_DAY_BUCKETS + 1);

    pruneOldDays(state, NOW);
    expect(summarizeDay(state, DAY, CONFIG).hardCapReached).toBe(false);
    expect(reserveAttempt(state, 'new-a', 0.1, DAY, CONFIG, 'generate', NOW)).toEqual({ ok: true });
  });

  it('(b) open tomorrow plus 31 window buckets allows new hold after tomorrow reconciles', () => {
    const state = emptyLedgerState();
    fillProtectedWindowSettled(state);
    const tomorrow = utcDayKeyMinusDays(DAY, -1);
    state.days[tomorrow] = openDay(tomorrow, 'tomorrow-open');
    expect(Object.keys(state.days).length).toBe(LEDGER_DAY_BUCKETS + 1);

    expect(reconcileAttempt(state, 'tomorrow-open', 0.02)).toEqual({ ok: true });
    expect(Object.keys(state.days).length).toBe(LEDGER_DAY_BUCKETS + 1);
    expect(summarizeDay(state, DAY, CONFIG).hardCapReached).toBe(false);
    expect(reserveAttempt(state, 'new-b', 0.1, DAY, CONFIG, 'generate', NOW)).toEqual({ ok: true });
  });

  it('(c) aged open unknown plus 31 window buckets allows new hold indefinitely when under cap', () => {
    const state = emptyLedgerState();
    fillProtectedWindowSettled(state);
    const staleOpenKey = utcDayKeyMinusDays(DAY, 35);
    state.days[staleOpenKey] = openDay(staleOpenKey, 'stale-unknown', 'unknown');
    expect(Object.keys(state.days).length).toBe(LEDGER_DAY_BUCKETS + 1);

    pruneOldDays(state, NOW);
    expect(summarizeDay(state, DAY, CONFIG).hardCapReached).toBe(false);
    expect(reserveAttempt(state, 'new-c', 0.1, DAY, CONFIG, 'generate', NOW)).toEqual({ ok: true });
  });

  it('summary hardCapReached matches reserve hard_cap when money cap is full', () => {
    const state = emptyLedgerState();
    fillProtectedWindowSettled(state);
    state.days[DAY]!.spentMicro = 1_000_000;
    expect(summarizeDay(state, DAY, CONFIG).hardCapReached).toBe(true);
    expect(reserveAttempt(state, 'blocked-money', 0.01, DAY, CONFIG, 'generate', NOW)).toEqual({
      ok: false,
      reason: 'hard_cap',
    });
  });

  it('age-based prune leaves no settled buckets outside the protected window', () => {
    const state = emptyLedgerState();
    for (let age = 0; age <= 45; age += 1) {
      const dayKey = utcDayKeyMinusDays(DAY, age);
      state.days[dayKey] = settledDay(dayKey);
    }
    pruneOldDays(state, NOW);
    expect(countSettledBucketsOutsideEvictionWindow(state, NOW)).toBe(0);
    expect(Object.keys(state.days).length).toBeLessThanOrEqual(LEDGER_DAY_BUCKETS + 1);
  });
});

/**
 * Regression tests for bucket-count lockout (QA fix/13a-bucket-limit-lockout).
 */

import { describe, it, expect } from 'vitest';
import {
  ageLedger,
  countSettledBucketsOutsideEvictionWindow,
  emptyLedgerState,
  MAX_ATTEMPTS_PER_DAY,
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

    expect(reconcileAttempt(state, tomorrow, 'tomorrow-open', 0.02)).toEqual({ ok: true });
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

describe('ledger storage bounds', () => {
  it('one open hold per day for 65 simulated UTC days keeps buckets within the window', () => {
    const state = emptyLedgerState();
    let now = new Date('2026-01-01T12:00:00.000Z');
    for (let i = 0; i < 65; i += 1) {
      const dayKey = now.toISOString().split('T')[0];
      expect(reserveAttempt(state, `open-${i}`, 0.01, dayKey, CONFIG, 'generate', now)).toEqual({
        ok: true,
      });
      ageLedger(state, now);
      now = new Date(now.getTime() + 86_400_000);
    }
    ageLedger(state, now);
    expect(Object.keys(state.days).length).toBeLessThanOrEqual(LEDGER_DAY_BUCKETS + 1);
    let attemptRecords = 0;
    for (const day of Object.values(state.days)) {
      attemptRecords += Object.keys(day.attempts).length;
    }
    expect(attemptRecords).toBeLessThanOrEqual((LEDGER_DAY_BUCKETS + 1) * MAX_ATTEMPTS_PER_DAY);
  });

  it('expires stale open holds at the full reserved upper bound then prunes the bucket', () => {
    const state = emptyLedgerState();
    const staleKey = utcDayKeyMinusDays(DAY, 35);
    state.days[staleKey] = openDay(staleKey, 'stale-reserved');
    expect(state.days[staleKey].reservedMicro).toBe(50_000);
    expect(pruneOldDays(state, NOW)).toBe(true);
    expect(state.days[staleKey]).toBeUndefined();
  });

  it('late reconcile after expiry and prune returns not_found without mutating state', () => {
    const state = emptyLedgerState();
    const staleKey = utcDayKeyMinusDays(DAY, 35);
    state.days[staleKey] = openDay(staleKey, 'gone');
    pruneOldDays(state, NOW);
    const snapshot = JSON.stringify(state);
    expect(reconcileAttempt(state, staleKey, 'gone', 0.01)).toEqual({ ok: false, reason: 'not_found' });
    expect(JSON.stringify(state)).toBe(snapshot);
  });

  it('attempt_limit blocks new holds while idempotent retry stays ok and summary agrees', () => {
    const state = emptyLedgerState();
    const day = state.days[DAY] ?? {
      date: DAY,
      spentMicro: 0,
      reservedMicro: 0,
      overReservationCount: 0,
      attempts: Object.create(null),
      tasks: Object.create(null),
    };
    state.days[DAY] = day;
    for (let i = 0; i < MAX_ATTEMPTS_PER_DAY - 1; i += 1) {
      day.attempts[`fill-${i}`] = {
        attemptId: `fill-${i}`,
        upperBoundMicro: 1,
        actualMicro: 1,
        task: 'generate',
        state: 'reconciled',
        createdAt: NOW.toISOString(),
      };
    }
    expect(reserveAttempt(state, 'keep', 0.000001, DAY, CONFIG, 'generate', NOW)).toEqual({ ok: true });
    expect(summarizeDay(state, DAY, CONFIG).attemptLimitReached).toBe(true);
    expect(reserveAttempt(state, 'extra', 0.000001, DAY, CONFIG, 'generate', NOW)).toEqual({
      ok: false,
      reason: 'attempt_limit',
    });
    expect(reserveAttempt(state, 'keep', 0.000001, DAY, CONFIG, 'generate', NOW)).toEqual({ ok: true });
  });

  it('stale expiry with spentMicro overflow still prunes buckets beyond the window', () => {
    const state = emptyLedgerState();
    const staleKey = utcDayKeyMinusDays(DAY, 35);
    const upper = 50_000;
    state.days[staleKey] = openDay(staleKey, 'overflow-open');
    state.days[staleKey].spentMicro = Number.MAX_SAFE_INTEGER - 10;
    state.days[staleKey].reservedMicro = upper;
    for (let age = 0; age <= 30; age += 1) {
      const dayKey = utcDayKeyMinusDays(DAY, age);
      if (!state.days[dayKey]) {
        state.days[dayKey] = settledDay(dayKey);
      }
    }
    expect(pruneOldDays(state, NOW)).toBe(true);
    expect(state.days[staleKey]).toBeUndefined();
    expect(Object.keys(state.days).length).toBeLessThanOrEqual(LEDGER_DAY_BUCKETS + 1);
  });

  it('late reconcile is scoped to reservation day and cannot touch a reused attemptId', () => {
    const state = emptyLedgerState();
    const oldDay = utcDayKeyMinusDays(DAY, 40);
    state.days[oldDay] = openDay(oldDay, 'shared-id');
    pruneOldDays(state, NOW);
    expect(findAttemptState(state, oldDay, 'shared-id')).toBeNull();
    expect(reserveAttempt(state, 'shared-id', 0.1, DAY, CONFIG, 'generate', NOW)).toEqual({ ok: true });
    const reservedBefore = state.days[DAY]?.reservedMicro ?? 0;
    expect(reconcileAttempt(state, oldDay, 'shared-id', 0.05)).toEqual({ ok: false, reason: 'not_found' });
    expect(state.days[DAY]?.reservedMicro).toBe(reservedBefore);
    expect(state.days[DAY]?.attempts['shared-id']?.state).toBe('reserved');
  });
});

function findAttemptState(
  state: ReturnType<typeof emptyLedgerState>,
  dayKey: string,
  attemptId: string
): unknown {
  return state.days[dayKey]?.attempts[attemptId] ?? null;
}

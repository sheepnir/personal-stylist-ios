/**
 * Unit tests for spend ledger core logic (#13-a).
 */

import { describe, it, expect } from 'vitest';
import {
  ageLedger,
  actualUsdToMicro,
  capUsdToMicro,
  costUsdToMicro,
  emptyLedgerState,
  ledgerExceedsBucketLimit,
  pruneOldDays,
  reconcileAttempt,
  removeEmptyDayBucket,
  reserveAttempt,
  summarizeDay,
  isValidLedgerDayKey,
  LEDGER_DAY_BUCKETS,
  LEDGER_MAX_DAY_AGE,
  MICRO_USD,
  usdToMicro,
} from '../src/ledgerCore.js';

const DAY = '2026-09-26';
const CONFIG = { dailyCapUSD: 1.0, softThresholdUSD: 0.5 };

describe('ledgerCore USD ↔ micro-USD conversion', () => {
  it('converts 0.1, 0.2 and 0.3 exactly', () => {
    expect(costUsdToMicro(0.1)).toEqual({ ok: true, micro: 100_000 });
    expect(costUsdToMicro(0.2)).toEqual({ ok: true, micro: 200_000 });
    expect(costUsdToMicro(0.3)).toEqual({ ok: true, micro: 300_000 });
  });

  it('costUsdToMicro ceils tiny positive costs to at least 1 micro', () => {
    expect(costUsdToMicro(1e-9)).toEqual({ ok: true, micro: 1 });
    expect(costUsdToMicro(0.0000004)).toEqual({ ok: true, micro: 1 });
  });

  it('reconcile attempt 1000 at 0.0004 USD records at least 400 micro', () => {
    const state = emptyLedgerState();
    reserveAttempt(state, '1000', 0.001, DAY, CONFIG);
    reconcileAttempt(state, '1000', 0.0004);
    expect(state.days[DAY].spentMicro).toBeGreaterThanOrEqual(400);
  });

  it('refuses a second hold when 0.999999 and 0.0000014 exceed a 1.00 cap', () => {
    const state = emptyLedgerState();
    expect(reserveAttempt(state, 'a', 0.999999, DAY, CONFIG)).toEqual({ ok: true });
    expect(reserveAttempt(state, 'b', 0.0000014, DAY, CONFIG)).toEqual({ ok: false, reason: 'hard_cap' });
  });

  it('capUsdToMicro floors 0.9999995 to 999999 micro', () => {
    expect(capUsdToMicro(0.9999995)).toEqual({ ok: true, micro: 999_999 });
  });

  it('costUsdToMicro(1e-10) returns 1 micro', () => {
    expect(costUsdToMicro(1e-10)).toEqual({ ok: true, micro: 1 });
  });

  it('0.10 + 0.20 versus 0.30 micro-USD regression', () => {
    const state = emptyLedgerState();
    expect(reserveAttempt(state, 'ten-cents', 0.1, DAY, CONFIG)).toEqual({ ok: true });
    expect(reserveAttempt(state, 'twenty-cents', 0.2, DAY, CONFIG)).toEqual({ ok: true });
    expect(summarizeDay(state, DAY, CONFIG).reservedUSD).toBeCloseTo(0.3);
    expect(costUsdToMicro(0.1).ok && costUsdToMicro(0.2).ok && costUsdToMicro(0.3).ok).toBe(true);
    if (costUsdToMicro(0.1).ok && costUsdToMicro(0.2).ok && costUsdToMicro(0.3).ok) {
      expect(costUsdToMicro(0.1).micro + costUsdToMicro(0.2).micro).toBe(costUsdToMicro(0.3).micro);
    }
  });
});

describe('ledgerCore reserve / reconcile', () => {
  it('reserves an upper bound and reconciles to actual cost', () => {
    const state = emptyLedgerState();
    expect(reserveAttempt(state, 'a1', 0.4, DAY, CONFIG, 'generate')).toEqual({ ok: true });
    let summary = summarizeDay(state, DAY, CONFIG);
    expect(summary.spentUSD).toBe(0);
    expect(summary.reservedUSD).toBeCloseTo(0.4);

    expect(reconcileAttempt(state, 'a1', 0.12)).toEqual({ ok: true });
    summary = summarizeDay(state, DAY, CONFIG);
    expect(summary.spentUSD).toBeCloseTo(0.12);
    expect(summary.reservedUSD).toBeCloseTo(0);
    expect(summary.byTask.generate).toBeCloseTo(0.12);
  });

  it('sets per-attempt overReservation flag when actual exceeds bound', () => {
    const state = emptyLedgerState();
    reserveAttempt(state, 'a1', 0.2, DAY, CONFIG);
    reconcileAttempt(state, 'a1', 0.35);
    const entry = state.days[DAY].attempts.a1;
    expect(entry.overReservation).toBe(true);
    expect(summarizeDay(state, DAY, CONFIG).overReservationCount).toBe(1);
  });

  it('accepts reconcile actual cost above 10000 USD when representable in micro-USD', () => {
    const state = emptyLedgerState();
    reserveAttempt(state, 'big', 0.01, DAY, { dailyCapUSD: 20_000, softThresholdUSD: 10_000 });
    const actualUsd = 15_000;
    expect(actualUsdToMicro(actualUsd).ok).toBe(true);
    expect(reconcileAttempt(state, 'big', actualUsd)).toEqual({ ok: true });
    expect(state.days[DAY].spentMicro).toBe(15_000 * MICRO_USD);
    expect(state.days[DAY].attempts.big.overReservation).toBe(true);
  });

  it('rejects reconcile at zero or negative zero USD without releasing the hold', () => {
    const state = emptyLedgerState();
    reserveAttempt(state, 'z', 0.1, DAY, CONFIG);
    const reservedBefore = state.days[DAY].reservedMicro;
    expect(reconcileAttempt(state, 'z', 0)).toEqual({ ok: false, reason: 'invalid' });
    expect(reconcileAttempt(state, 'z', -0)).toEqual({ ok: false, reason: 'invalid' });
    expect(state.days[DAY].reservedMicro).toBe(reservedBefore);
    expect(state.days[DAY].attempts.z.state).toBe('reserved');
  });

  it('rejects reconcile task override with unsafe task name', () => {
    const state = emptyLedgerState();
    reserveAttempt(state, 'a1', 0.2, DAY, CONFIG, 'generate');
    expect(reconcileAttempt(state, 'a1', 0.1, '__proto__')).toEqual({ ok: false, reason: 'invalid' });
  });

  it('idempotent reserve retry succeeds after reservation day becomes past or bucket limit is hit', () => {
    const reserveDay = utcDayKeyMinusDays(DAY, -1);
    const nowAtReserve = new Date(`${DAY}T12:00:00.000Z`);
    const state = emptyLedgerState();
    expect(
      reserveAttempt(state, 'retry-1', 0.2, reserveDay, CONFIG, 'generate', nowAtReserve)
    ).toEqual({ ok: true });

    for (let age = 0; age <= 30; age += 1) {
      const dayKey = utcDayKeyMinusDays(DAY, age);
      if (state.days[dayKey]) {
        continue;
      }
      state.days[dayKey] = settledDay(dayKey, 1);
    }
    expect(ledgerExceedsBucketLimit(state)).toBe(true);
    expect(
      reserveAttempt(state, 'retry-1', 0.2, reserveDay, CONFIG, 'generate', nowAtReserve)
    ).toEqual({ ok: true });

    const nowPastReservationDay = new Date(`2026-09-28T12:00:00.000Z`);
    expect(
      reserveAttempt(state, 'retry-1', 0.2, reserveDay, CONFIG, 'generate', nowPastReservationDay)
    ).toEqual({ ok: true });
    expect(
      reserveAttempt(state, 'new-hold', 0.01, '2026-09-28', CONFIG, 'generate', nowPastReservationDay)
    ).toEqual({ ok: false, reason: 'hard_cap' });
  });

  it('rejects unsafe reserve task names', () => {
    const state = emptyLedgerState();
    for (const task of ['__proto__', 'constructor', 'prototype']) {
      expect(reserveAttempt(state, `a-${task}`, 0.1, DAY, CONFIG, task)).toEqual({
        ok: false,
        reason: 'invalid',
      });
    }
  });

  it('rejects reserve when spent + reserved + upper bound exceeds hard cap', () => {
    const state = emptyLedgerState();
    expect(reserveAttempt(state, 'a1', 0.6, DAY, CONFIG)).toEqual({ ok: true });
    expect(reserveAttempt(state, 'a2', 0.5, DAY, CONFIG)).toEqual({ ok: false, reason: 'hard_cap' });
  });

  it('allows ten 0.1 reservations to exactly fill a 1.0 cap (micro-USD)', () => {
    const state = emptyLedgerState();
    for (let i = 0; i < 10; i += 1) {
      expect(reserveAttempt(state, `a${i}`, 0.1, DAY, CONFIG)).toEqual({ ok: true });
    }
    expect(reserveAttempt(state, 'extra', 0.1, DAY, CONFIG)).toEqual({ ok: false, reason: 'hard_cap' });
    expect(summarizeDay(state, DAY, CONFIG).reservedUSD).toBeCloseTo(1.0);
  });

  it('does not leave an empty day bucket after a rejected reserve', () => {
    const state = emptyLedgerState();
    expect(reserveAttempt(state, 'a1', 999, DAY, CONFIG)).toEqual({ ok: false, reason: 'hard_cap' });
    removeEmptyDayBucket(state, DAY);
    expect(state.days[DAY]).toBeUndefined();
  });

  it('returns already_settled when re-reserving a reconciled attemptId', () => {
    const state = emptyLedgerState();
    reserveAttempt(state, 'done', 0.2, DAY, CONFIG);
    reconcileAttempt(state, 'done', 0.15);
    expect(reserveAttempt(state, 'done', 0.2, DAY, CONFIG)).toEqual({
      ok: false,
      reason: 'already_settled',
    });
  });

  it('refuses reserve when config cap is NaN (defense in depth)', () => {
    const state = emptyLedgerState();
    expect(
      reserveAttempt(state, 'a1', 0.1, DAY, { dailyCapUSD: Number.NaN, softThresholdUSD: 0.5 })
    ).toEqual({ ok: false, reason: 'config_error' });
    expect(summarizeDay(state, DAY, { dailyCapUSD: Number.NaN, softThresholdUSD: 0.5 }).hardCapReached).toBe(
      true
    );
  });

  it('refuses second reconcile when spentMicro sum would exceed MAX_SAFE_INTEGER', () => {
    const state = emptyLedgerState();
    reserveAttempt(state, 'big1', 0.01, DAY, CONFIG);
    reserveAttempt(state, 'big2', 0.01, DAY, CONFIG);
    reconcileAttempt(state, 'big1', 0.01);
    const day = state.days[DAY];
    day.spentMicro = Number.MAX_SAFE_INTEGER - 500;
    day.reservedMicro = 0;
    day.attempts.big2.state = 'reserved';
    expect(reconcileAttempt(state, 'big2', 0.01)).toEqual({ ok: false, reason: 'overflow' });
    expect(day.spentMicro).toBe(Number.MAX_SAFE_INTEGER - 500);
  });
});

describe('ledgerCore future day keys', () => {
  const NOW = new Date(`${DAY}T12:00:00.000Z`);

  it('rejects reserve on a day more than one UTC day ahead', () => {
    const state = emptyLedgerState();
    expect(reserveAttempt(state, 'a1', 0.1, '2026-09-28', CONFIG, 'unknown', NOW)).toEqual({
      ok: false,
      reason: 'invalid',
    });
  });

  it('rejects reserve on a UTC day before today', () => {
    const now = new Date(`${DAY}T12:00:00.000Z`);
    const state = emptyLedgerState();
    const pastDay = utcDayKeyMinusDays(DAY, 40);
    expect(reserveAttempt(state, 'past', 0.1, pastDay, CONFIG, 'generate', now)).toEqual({
      ok: false,
      reason: 'invalid',
    });
  });

  it('prunes settled future days beyond one day ahead', () => {
    const state = emptyLedgerState();
    state.days['2099-01-01'] = {
      date: '2099-01-01',
      spentMicro: 100,
      reservedMicro: 0,
      overReservationCount: 0,
      attempts: Object.create(null),
      tasks: Object.create(null),
    };
    pruneOldDays(state, NOW);
    expect(state.days['2099-01-01']).toBeUndefined();
  });

  it('never retains more than 31 day buckets', () => {
    const state = emptyLedgerState();
    for (let i = 0; i < 40; i += 1) {
      const d = `2026-08-${String(i + 1).padStart(2, '0')}`;
      if (!isValidLedgerDayKey(d)) continue;
      state.days[d] = {
        date: d,
        spentMicro: 1,
        reservedMicro: 0,
        overReservationCount: 0,
        attempts: Object.create(null),
        tasks: Object.create(null),
      };
    }
    pruneOldDays(state, NOW);
    expect(Object.keys(state.days).length).toBeLessThanOrEqual(LEDGER_DAY_BUCKETS);
  });
});

describe('ledgerCore retention', () => {
  it(`retains exactly ${LEDGER_DAY_BUCKETS} UTC day buckets (today + ${LEDGER_MAX_DAY_AGE} preceding)`, () => {
    const state = emptyLedgerState();
    const now = new Date(`${DAY}T12:00:00.000Z`);
    const keepDay = '2026-08-27'; // age 30 from 2026-09-26
    const dropDay = '2026-08-26'; // age 31
    for (const key of [keepDay, dropDay]) {
      state.days[key] = {
        date: key,
        spentMicro: 1000,
        reservedMicro: 0,
        overReservationCount: 0,
        attempts: {},
        tasks: Object.create(null),
      };
    }
    expect(pruneOldDays(state, now)).toBe(true);
    expect(state.days[keepDay]).toBeDefined();
    expect(state.days[dropDay]).toBeUndefined();
  });

  it('never prunes malformed buckets with unknown attempts', () => {
    const state = emptyLedgerState();
    state.days['bad-key'] = {
      date: 'bad-key',
      spentMicro: 0,
      reservedMicro: 200_000,
      overReservationCount: 0,
      attempts: {
        open: {
          attemptId: 'open',
          upperBoundMicro: 200_000,
          task: 'generate',
          state: 'unknown',
          createdAt: new Date().toISOString(),
        },
      },
      tasks: Object.create(null),
    };
    pruneOldDays(state, new Date(`${DAY}T00:00:00.000Z`));
    expect(state.days['bad-key']).toBeDefined();
    expect(reserveAttempt(state, 'open', 0.2, DAY, CONFIG)).toEqual({ ok: false, reason: 'already_settled' });
  });

  it('removes settled malformed buckets with no open attempts', () => {
    const state = emptyLedgerState();
    state.days['bad-key'] = {
      date: 'bad-key',
      spentMicro: 1000,
      reservedMicro: 0,
      overReservationCount: 0,
      attempts: {},
      tasks: Object.create(null),
    };
    expect(pruneOldDays(state, new Date(`${DAY}T00:00:00.000Z`))).toBe(true);
    expect(state.days['bad-key']).toBeUndefined();
  });

  it('ageLedger returns whether pruning changed storage', () => {
    const state = emptyLedgerState();
    state.days['1999-01-01'] = {
      date: '1999-01-01',
      spentMicro: 1,
      reservedMicro: 0,
      overReservationCount: 0,
      attempts: {},
      tasks: Object.create(null),
    };
    expect(ageLedger(state, new Date(`${DAY}T00:00:00.000Z`))).toBe(true);
    expect(state.days['1999-01-01']).toBeUndefined();
  });

  it('does not delete today when 31 stale open buckets exceed the bucket limit', () => {
    const now = new Date(`${DAY}T12:00:00.000Z`);
    const state = emptyLedgerState();
    const capMicro = 1_000_000;

    for (let offset = 1; offset <= 31; offset += 1) {
      const dayKey = utcDayKeyMinusDays(DAY, offset);
      state.days[dayKey] = openReservedDay(dayKey, `stale-${offset}`, 10_000);
    }

    state.days[DAY] = {
      date: DAY,
      spentMicro: capMicro,
      reservedMicro: 0,
      overReservationCount: 0,
      attempts: {
        settled: {
          attemptId: 'settled',
          upperBoundMicro: capMicro,
          actualMicro: capMicro,
          task: 'generate',
          state: 'reconciled',
          createdAt: now.toISOString(),
          reconciledAt: now.toISOString(),
        },
      },
      tasks: Object.create(null),
    };
    state.days[DAY].tasks.generate = capMicro;

    pruneOldDays(state, now);

    expect(state.days[DAY]).toBeDefined();
    expect(state.days[DAY].spentMicro).toBe(capMicro);
    expect(ledgerExceedsBucketLimit(state)).toBe(true);
    expect(summarizeDay(state, DAY, CONFIG).hardCapReached).toBe(true);
    expect(reserveAttempt(state, 'blocked', 0.01, DAY, CONFIG, 'unknown', now)).toEqual({
      ok: false,
      reason: 'hard_cap',
    });
  });

  it('evicts oldest settled buckets first without dropping settled days inside the 30-day window', () => {
    const now = new Date(`${DAY}T12:00:00.000Z`);
    const state = emptyLedgerState();

    for (let age = 0; age <= 30; age += 1) {
      const dayKey = utcDayKeyMinusDays(DAY, age);
      state.days[dayKey] = settledDay(dayKey, age === 0 ? 1_000_000 : 1000);
    }

    const staleOpenKey = utcDayKeyMinusDays(DAY, 40);
    state.days[staleOpenKey] = openReservedDay(staleOpenKey, 'stale-open', 50_000);

    const tomorrow = utcDayKeyMinusDays(DAY, -1);
    state.days[tomorrow] = settledDay(tomorrow, 500);

    const age29Key = utcDayKeyMinusDays(DAY, 29);
    const age30Key = utcDayKeyMinusDays(DAY, 30);

    pruneOldDays(state, now);

    expect(state.days[age29Key]).toBeDefined();
    expect(state.days[age30Key]).toBeDefined();
    expect(state.days[DAY]?.spentMicro).toBe(1_000_000);
    expect(state.days[tomorrow]).toBeDefined();
    expect(state.days[tomorrow]?.spentMicro).toBe(500);
    expect(state.days[staleOpenKey]).toBeDefined();
  });
});

function utcDayKeyMinusDays(day: string, daysBack: number): string {
  const ms = Date.parse(`${day}T00:00:00.000Z`) - daysBack * 86_400_000;
  return new Date(ms).toISOString().split('T')[0];
}

function openReservedDay(dayKey: string, attemptId: string, upperBoundMicro: number) {
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
        state: 'reserved' as const,
        createdAt: new Date().toISOString(),
      },
    },
    tasks: Object.create(null),
  };
}

function settledDay(dayKey: string, spentMicro: number) {
  return {
    date: dayKey,
    spentMicro,
    reservedMicro: 0,
    overReservationCount: 0,
    attempts: {},
    tasks: Object.create(null),
  };
}

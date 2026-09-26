/**
 * Unit tests for spend ledger core logic (#13-a).
 */

import { describe, it, expect } from 'vitest';
import {
  ageLedger,
  capUsdToMicro,
  costUsdToMicro,
  emptyLedgerState,
  pruneOldDays,
  reconcileAttempt,
  removeEmptyDayBucket,
  reserveAttempt,
  summarizeDay,
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

  it('tracks task named constructor without prototype pollution', () => {
    const state = emptyLedgerState();
    reserveAttempt(state, 'a1', 0.2, DAY, CONFIG, 'constructor');
    reconcileAttempt(state, 'a1', 0.15, 'constructor');
    const summary = summarizeDay(state, DAY, CONFIG);
    expect(summary.byTask.constructor).toBeCloseTo(0.15);
    expect(Object.prototype.hasOwnProperty.call(summary.byTask, 'constructor')).toBe(true);
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
});

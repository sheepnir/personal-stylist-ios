/**
 * Unit tests for spend ledger core logic (#13-a).
 */

import { describe, it, expect } from 'vitest';
import {
  ageLedger,
  emptyLedgerState,
  pruneOldDays,
  reconcileAttempt,
  reserveAttempt,
  summarizeDay,
  LEDGER_RETENTION_DAYS,
  usdToMicro,
} from '../src/ledgerCore.js';

const DAY = '2026-09-26';
const CONFIG = { dailyCapUSD: 1.0, softThresholdUSD: 0.5 };

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
    const summary = summarizeDay(state, DAY, CONFIG);
    expect(summary.reservedUSD).toBeCloseTo(1.0);
    expect(usdToMicro(summary.reservedUSD)).toBe(usdToMicro(1.0));
  });

  it('enforces soft threshold against spent + reserved', () => {
    const state = emptyLedgerState();
    reserveAttempt(state, 'a1', 0.5, DAY, CONFIG);
    const summary = summarizeDay(state, DAY, CONFIG);
    expect(summary.softThresholdReached).toBe(true);
    expect(summary.hardCapReached).toBe(false);
  });

  it('uses a configured cap from SpendConfig', () => {
    const state = emptyLedgerState();
    const tight = { dailyCapUSD: 0.2, softThresholdUSD: 0.1 };
    expect(reserveAttempt(state, 'a1', 0.15, DAY, tight)).toEqual({ ok: true });
    expect(reserveAttempt(state, 'a2', 0.06, DAY, tight)).toEqual({ ok: false, reason: 'hard_cap' });
  });

  it('is idempotent on duplicate reserve with the same attemptId', () => {
    const state = emptyLedgerState();
    expect(reserveAttempt(state, 'a1', 0.2, DAY, CONFIG)).toEqual({ ok: true });
    expect(reserveAttempt(state, 'a1', 0.2, DAY, CONFIG)).toEqual({ ok: true });
    expect(summarizeDay(state, DAY, CONFIG).reservedUSD).toBeCloseTo(0.2);
  });

  it('is idempotent on duplicate reconcile with the same actualUSD', () => {
    const state = emptyLedgerState();
    reserveAttempt(state, 'a1', 0.3, DAY, CONFIG);
    expect(reconcileAttempt(state, 'a1', 0.11)).toEqual({ ok: true });
    expect(reconcileAttempt(state, 'a1', 0.11)).toEqual({ ok: true });
    expect(summarizeDay(state, DAY, CONFIG).spentUSD).toBeCloseTo(0.11);
  });

  it('records full actual cost when reconcile exceeds the reservation', () => {
    const state = emptyLedgerState();
    reserveAttempt(state, 'a1', 0.2, DAY, CONFIG);
    expect(reconcileAttempt(state, 'a1', 0.35)).toEqual({ ok: true });
    const summary = summarizeDay(state, DAY, CONFIG);
    expect(summary.spentUSD).toBeCloseTo(0.35);
    expect(summary.reservedUSD).toBeCloseTo(0);
    expect(summary.overReservationCount).toBe(1);
  });

  it('sets hardCapReached from spent alone when reconcile crosses the cap', () => {
    const state = emptyLedgerState();
    reserveAttempt(state, 'a1', 0.5, DAY, CONFIG);
    expect(reconcileAttempt(state, 'a1', 1.2)).toEqual({ ok: true });
    const summary = summarizeDay(state, DAY, CONFIG);
    expect(summary.spentUSD).toBeCloseTo(1.2);
    expect(summary.hardCapReached).toBe(true);
  });

  it('refuses further reserve after spent reaches the cap via over-reconcile', () => {
    const state = emptyLedgerState();
    reserveAttempt(state, 'a1', 0.3, DAY, CONFIG);
    reconcileAttempt(state, 'a1', 1.0);
    expect(reserveAttempt(state, 'a2', 0.01, DAY, CONFIG)).toEqual({ ok: false, reason: 'hard_cap' });
  });

  it('does not double-reserve the same attemptId on a different UTC day', () => {
    const state = emptyLedgerState();
    expect(reserveAttempt(state, 'cross-day', 0.25, '2026-09-25', CONFIG)).toEqual({ ok: true });
    expect(reserveAttempt(state, 'cross-day', 0.25, DAY, CONFIG)).toEqual({ ok: true });
    expect(summarizeDay(state, DAY, CONFIG).reservedUSD).toBeCloseTo(0);
    expect(summarizeDay(state, '2026-09-25', CONFIG).reservedUSD).toBeCloseTo(0.25);
  });
});

describe('ledgerCore retention', () => {
  it(`keeps buckets exactly ${LEDGER_RETENTION_DAYS} UTC days old and prunes older`, () => {
    const state = emptyLedgerState();
    const now = new Date(`${DAY}T12:00:00.000Z`);
    state.days['2026-08-26'] = {
      date: '2026-08-26',
      spentMicro: usdToMicro(0.1),
      reservedMicro: 0,
      overReservationCount: 0,
      attempts: {},
      tasks: {},
    };
    state.days['2026-08-25'] = {
      date: '2026-08-25',
      spentMicro: usdToMicro(9),
      reservedMicro: 0,
      overReservationCount: 0,
      attempts: {},
      tasks: {},
    };
    pruneOldDays(state, now);
    expect(state.days['2026-08-26']).toBeDefined();
    expect(state.days['2026-08-25']).toBeUndefined();
  });

  it('ageLedger prunes stale buckets even when no mutation follows', () => {
    const state = emptyLedgerState();
    state.days['1999-12-31'] = {
      date: '1999-12-31',
      spentMicro: usdToMicro(1),
      reservedMicro: 0,
      overReservationCount: 0,
      attempts: {},
      tasks: {},
    };
    ageLedger(state, new Date(`${DAY}T00:00:00.000Z`));
    expect(state.days['1999-12-31']).toBeUndefined();
  });

  it('persists pruning after a failed reserve (state mutation in caller)', () => {
    const state = emptyLedgerState();
    state.days['1999-01-01'] = {
      date: '1999-01-01',
      spentMicro: 0,
      reservedMicro: 0,
      overReservationCount: 0,
      attempts: {},
      tasks: {},
    };
    ageLedger(state, new Date(`${DAY}T00:00:00.000Z`));
    expect(reserveAttempt(state, 'a1', 999, DAY, CONFIG)).toEqual({ ok: false, reason: 'hard_cap' });
    expect(state.days['1999-01-01']).toBeUndefined();
  });
});

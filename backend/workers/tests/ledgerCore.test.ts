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
} from '../src/ledgerCore.js';

const DAY = '2026-09-26';
const CONFIG = { dailyCapUSD: 1.0, softThresholdUSD: 0.5 };

describe('ledgerCore reserve / reconcile', () => {
  it('reserves an upper bound and reconciles to actual cost', () => {
    const state = emptyLedgerState();
    expect(reserveAttempt(state, 'a1', 0.4, DAY, CONFIG)).toEqual({ ok: true });
    let summary = summarizeDay(state, DAY, CONFIG);
    expect(summary.spentUSD).toBe(0);
    expect(summary.reservedUSD).toBeCloseTo(0.4);

    expect(reconcileAttempt(state, 'a1', 0.12)).toEqual({ ok: true });
    summary = summarizeDay(state, DAY, CONFIG);
    expect(summary.spentUSD).toBeCloseTo(0.12);
    expect(summary.reservedUSD).toBeCloseTo(0);
  });

  it('rejects reserve when spent + reserved + upper bound exceeds hard cap', () => {
    const state = emptyLedgerState();
    expect(reserveAttempt(state, 'a1', 0.6, DAY, CONFIG)).toEqual({ ok: true });
    expect(reserveAttempt(state, 'a2', 0.5, DAY, CONFIG)).toEqual({ ok: false, reason: 'hard_cap' });
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
});

describe('ledgerCore retention', () => {
  it(`prunes day records older than ${LEDGER_RETENTION_DAYS} days on write`, () => {
    const state = emptyLedgerState();
    state.days['2020-01-01'] = {
      date: '2020-01-01',
      spentUSD: 9,
      reservedUSD: 0,
      attempts: {},
      tasks: {},
    };
    state.days[DAY] = {
      date: DAY,
      spentUSD: 0.1,
      reservedUSD: 0,
      attempts: {},
      tasks: {},
    };
    pruneOldDays(state, new Date(`${DAY}T12:00:00.000Z`));
    expect(state.days['2020-01-01']).toBeUndefined();
    expect(state.days[DAY]?.spentUSD).toBeCloseTo(0.1);
  });

  it('ageLedger prunes stale buckets', () => {
    const state = emptyLedgerState();
    state.days['1999-12-31'] = {
      date: '1999-12-31',
      spentUSD: 1,
      reservedUSD: 0,
      attempts: {},
      tasks: {},
    };
    ageLedger(state, new Date(`${DAY}T00:00:00.000Z`));
    expect(state.days['1999-12-31']).toBeUndefined();
  });
});

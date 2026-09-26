/**
 * Unit tests for spend ledger core logic (#13-a).
 */

import { describe, it, expect } from 'vitest';
import type { CostSource } from '../src/costSource.js';
import {
  ageLedger,
  emptyLedgerState,
  markAttemptUnknown,
  pruneOldDays,
  reconcileAttempt,
  reserveAttempt,
  summarizeDay,
  LEDGER_RETENTION_DAYS,
  UNKNOWN_OUTCOME_AGING_MS,
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
    ageLedger(state, new Date(`${DAY}T00:00:00.000Z`), { lookup: () => ({ outcome: 'unknown' }) });
    expect(state.days['1999-12-31']).toBeUndefined();
  });
});

describe('ledgerCore unknown outcomes (#13-b)', () => {
  const noopCost: CostSource = { lookup: () => ({ outcome: 'unknown' }) };

  it('keeps funds reserved when an outcome is marked unknown', () => {
    const state = emptyLedgerState();
    reserveAttempt(state, 'a1', 0.4, DAY, CONFIG);
    expect(markAttemptUnknown(state, 'a1', 'gen-1')).toEqual({ ok: true });

    const summary = summarizeDay(state, DAY, CONFIG);
    expect(summary.reservedUSD).toBeCloseTo(0.4);
    expect(summary.spentUSD).toBeCloseTo(0);
    expect(state.days[DAY]?.attempts.a1.state).toBe('unknown');
  });

  it('reconciles from mock CostSource when cost becomes known', () => {
    const state = emptyLedgerState();
    reserveAttempt(state, 'a1', 0.4, DAY, CONFIG);
    markAttemptUnknown(state, 'a1', 'gen-lookup');

    const base = new Date(`${DAY}T12:00:00.000Z`);
    state.days[DAY]!.attempts.a1.createdAt = new Date(`${DAY}T11:00:00.000Z`).toISOString();
    const costSource: CostSource = {
      lookup: (generationId, attemptId) => {
        expect(generationId).toBe('gen-lookup');
        expect(attemptId).toBe('a1');
        return { outcome: 'known', costUSD: 0.09 };
      },
    };
    ageLedger(state, base, costSource);

    const summary = summarizeDay(state, DAY, CONFIG);
    expect(summary.spentUSD).toBeCloseTo(0.09);
    expect(summary.reservedUSD).toBeCloseTo(0);
    expect(state.days[DAY]?.attempts.a1.state).toBe('reconciled');
  });

  it('does not release funds when CostSource returns error', () => {
    const state = emptyLedgerState();
    reserveAttempt(state, 'a1', 0.35, DAY, CONFIG);
    markAttemptUnknown(state, 'a1', 'gen-fail');

    const base = new Date(`${DAY}T12:00:00.000Z`);
    ageLedger(state, base, { lookup: () => ({ outcome: 'error' }) });

    let summary = summarizeDay(state, DAY, CONFIG);
    expect(summary.reservedUSD).toBeCloseTo(0.35);
    expect(summary.spentUSD).toBeCloseTo(0);

    ageLedger(state, new Date(base.getTime() + 60_000), { lookup: () => ({ outcome: 'error' }) });
    summary = summarizeDay(state, DAY, CONFIG);
    expect(summary.reservedUSD).toBeCloseTo(0.35);
  });

  it('ages unknown to spent at upper bound 24 h after reservation', () => {
    const state = emptyLedgerState();
    reserveAttempt(state, 'a1', 0.5, DAY, CONFIG);
    markAttemptUnknown(state, 'a1');

    const reservedAt = new Date(`${DAY}T10:00:00.000Z`);
    state.days[DAY]!.attempts.a1.createdAt = reservedAt.toISOString();

    const afterAging = new Date(reservedAt.getTime() + UNKNOWN_OUTCOME_AGING_MS + 1_000);
    ageLedger(state, afterAging, noopCost);

    const summary = summarizeDay(state, DAY, CONFIG);
    expect(summary.spentUSD).toBeCloseTo(0.5);
    expect(summary.reservedUSD).toBeCloseTo(0);
    expect(state.days[DAY]?.attempts.a1.actualUSD).toBeCloseTo(0.5);
  });

  it('counts aged spend against the ledger day of the reservation', () => {
    const reserveDay = '2026-09-25';
    const state = emptyLedgerState();
    reserveAttempt(state, 'a1', 0.3, reserveDay, CONFIG);
    markAttemptUnknown(state, 'a1');

    const reservedAt = new Date(`${reserveDay}T23:00:00.000Z`);
    state.days[reserveDay]!.attempts.a1.createdAt = reservedAt.toISOString();

    const afterAging = new Date(reservedAt.getTime() + UNKNOWN_OUTCOME_AGING_MS + 5_000);
    ageLedger(state, afterAging, noopCost);

    expect(summarizeDay(state, reserveDay, CONFIG).spentUSD).toBeCloseTo(0.3);
    expect(summarizeDay(state, '2026-09-26', CONFIG).spentUSD).toBeCloseTo(0);
  });

  it('ages to spent at 24 h when there is no generation id to look up', () => {
    const state = emptyLedgerState();
    reserveAttempt(state, 'timeout-1', 0.22, DAY, CONFIG);
    markAttemptUnknown(state, 'timeout-1');

    const reservedAt = new Date(`${DAY}T08:00:00.000Z`);
    state.days[DAY]!.attempts['timeout-1'].createdAt = reservedAt.toISOString();

    const spy: CostSource = {
      lookup: () => {
        throw new Error('must not call CostSource without generation id');
      },
    };
    const afterAging = new Date(reservedAt.getTime() + UNKNOWN_OUTCOME_AGING_MS);
    ageLedger(state, afterAging, spy);

    expect(summarizeDay(state, DAY, CONFIG).spentUSD).toBeCloseTo(0.22);
    expect(summarizeDay(state, DAY, CONFIG).reservedUSD).toBeCloseTo(0);
  });
});

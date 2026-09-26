import { describe, it, expect } from 'vitest';
import { createDeviceSpendLedgerHarness } from './helpers.js';
import { emptyLedgerState } from '../src/ledgerCore.js';

const DAY = '2026-09-26';
const CONFIG = { dailyCapUSD: 1.0, softThresholdUSD: 0.5 };
const BAD_CONFIG = { dailyCapUSD: Number.NaN, softThresholdUSD: 0.5 };

describe('DeviceSpendLedger persistence (fake DO storage)', () => {
  it('does not write storage when reserve fails without pruning', () => {
    const { ledger, putCount, resetPutCount } = createDeviceSpendLedgerHarness();
    resetPutCount();
    const result = ledger.reserve('fail-cap', 999, DAY, CONFIG);
    expect(result).toEqual({ ok: false, reason: 'hard_cap' });
    expect(putCount()).toBe(0);
  });

  it('writes storage on successful reserve', () => {
    const { ledger, putCount, resetPutCount, getStoredState } = createDeviceSpendLedgerHarness();
    resetPutCount();
    expect(ledger.reserve('ok-1', 0.1, DAY, CONFIG)).toEqual({ ok: true });
    expect(putCount()).toBe(1);
    expect(getStoredState()?.days[DAY]?.reservedMicro).toBeGreaterThan(0);
  });

  it('writes storage on successful reconcile', () => {
    const { ledger, putCount, resetPutCount } = createDeviceSpendLedgerHarness();
    expect(ledger.reserve('r1', 0.2, DAY, CONFIG)).toEqual({ ok: true });
    resetPutCount();
    expect(ledger.reconcile('r1', 0.05)).toEqual({ ok: true });
    expect(putCount()).toBe(1);
  });

  it('does not write when reconcile not_found and nothing pruned', () => {
    const { ledger, putCount, resetPutCount } = createDeviceSpendLedgerHarness();
    resetPutCount();
    expect(ledger.reconcile('nope', 0.01)).toEqual({ ok: false, reason: 'not_found' });
    expect(putCount()).toBe(0);
  });

  it('writes on real prune even when summary returns early for invalid config', () => {
    const state = emptyLedgerState();
    state.days['1999-01-01'] = {
      date: '1999-01-01',
      spentMicro: 1,
      reservedMicro: 0,
      overReservationCount: 0,
      attempts: Object.create(null),
      tasks: Object.create(null),
    };
    const { ledger, putCount, resetPutCount, getStoredState } = createDeviceSpendLedgerHarness(state);
    resetPutCount();
    ledger.summary(DAY, BAD_CONFIG);
    expect(putCount()).toBe(1);
    expect(getStoredState()?.days['1999-01-01']).toBeUndefined();
  });

  it('writes on real prune during reserve failure path after touch', () => {
    const state = emptyLedgerState();
    state.days['1999-01-01'] = {
      date: '1999-01-01',
      spentMicro: 1,
      reservedMicro: 0,
      overReservationCount: 0,
      attempts: Object.create(null),
      tasks: Object.create(null),
    };
    const { ledger, putCount, resetPutCount, getStoredState } = createDeviceSpendLedgerHarness(state);
    resetPutCount();
    expect(ledger.reserve('x', 999, DAY, CONFIG)).toEqual({ ok: false, reason: 'hard_cap' });
    expect(putCount()).toBe(1);
    expect(getStoredState()?.days['1999-01-01']).toBeUndefined();
  });

  it('invalid config reserve persists only when prune occurred (touch-before-early-return)', () => {
    const { ledger, putCount, resetPutCount } = createDeviceSpendLedgerHarness();
    resetPutCount();
    expect(ledger.reserve('cfg', 0.01, DAY, BAD_CONFIG)).toEqual({
      ok: false,
      reason: 'config_error',
    });
    expect(putCount()).toBe(0);

    const state = emptyLedgerState();
    state.days['1999-01-01'] = {
      date: '1999-01-01',
      spentMicro: 1,
      reservedMicro: 0,
      overReservationCount: 0,
      attempts: Object.create(null),
      tasks: Object.create(null),
    };
    const prunedHarness = createDeviceSpendLedgerHarness(state);
    prunedHarness.resetPutCount();
    expect(prunedHarness.ledger.reserve('cfg2', 0.01, DAY, BAD_CONFIG)).toEqual({
      ok: false,
      reason: 'config_error',
    });
    expect(prunedHarness.putCount()).toBe(1);
  });
});

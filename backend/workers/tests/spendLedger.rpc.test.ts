import { describe, it, expect } from 'vitest';
import { assertRpcPlainDeep } from '../src/rpcPlain.js';
import { emptyLedgerState, failClosedDaySummary } from '../src/ledgerCore.js';
import { createDeviceSpendLedgerHarness } from './helpers.js';

const DAY = '2026-09-26';
const CONFIG = { dailyCapUSD: 1.0, softThresholdUSD: 0.5 };
const BAD_CONFIG = { dailyCapUSD: Number.NaN, softThresholdUSD: 0.5 };

describe('DeviceSpendLedger RPC return values', () => {
  it('summary on empty ledger is structured-clone plain', () => {
    const { ledger } = createDeviceSpendLedgerHarness();
    const summary = ledger.summary(DAY, CONFIG);
    // structuredClone alone does not reject null-prototype objects; assertRpcPlainDeep does.
    expect(() => structuredClone(summary)).not.toThrow();
    assertRpcPlainDeep(summary);
  });

  it('fail-closed summary (invalid config) is structured-clone plain', () => {
    const { ledger } = createDeviceSpendLedgerHarness();
    const summary = ledger.summary(DAY, BAD_CONFIG);
    expect(summary.hardCapReached).toBe(true);
    assertRpcPlainDeep(summary);
  });

  it('internal failClosedDaySummary uses null-prototype byTask; DO summary is plain', () => {
    const internal = failClosedDaySummary(DAY);
    expect(Object.getPrototypeOf(internal.byTask)).not.toBe(Object.prototype);
    const { ledger } = createDeviceSpendLedgerHarness();
    const summary = ledger.summary(DAY, BAD_CONFIG);
    assertRpcPlainDeep(summary);
    expect(Object.getPrototypeOf(summary.byTask)).toBe(Object.prototype);
  });

  it('reserve and reconcile results are plain objects', () => {
    const { ledger } = createDeviceSpendLedgerHarness();
    assertRpcPlainDeep(ledger.reserve('a1', 0.01, DAY, CONFIG, 'generate'));
    assertRpcPlainDeep(ledger.reconcile(DAY, 'a1', 0.01, 'generate'));
    assertRpcPlainDeep(ledger.reserve('a2', 0.01, DAY, BAD_CONFIG));
    assertRpcPlainDeep(ledger.reconcile(DAY, 'missing', 0.01));
    assertRpcPlainDeep(ledger.markUnknown(DAY, 'x'));
  });

  it('RPC byTask omits unsafe keys from legacy storage without polluting clones', () => {
    const state = emptyLedgerState();
    const day = state.days[DAY] ?? {
      date: DAY,
      spentMicro: 2_000_000,
      reservedMicro: 0,
      overReservationCount: 0,
      attempts: Object.create(null),
      tasks: Object.create(null),
    };
    day.tasks['generate'] = 2_000_000;
    day.attempts['legacy-settle'] = {
      attemptId: 'legacy-settle',
      upperBoundMicro: 2_000_000,
      actualMicro: 2_000_000,
      task: 'generate',
      state: 'reconciled',
      createdAt: `${DAY}T12:00:00.000Z`,
      reconciledAt: `${DAY}T12:00:00.000Z`,
    };
    state.days[DAY] = day;

    const { ledger } = createDeviceSpendLedgerHarness(state);
    const summary = ledger.summary(DAY, CONFIG);
    assertRpcPlainDeep(summary);
    expect(Object.prototype.hasOwnProperty.call(summary.byTask, '__proto__')).toBe(false);
    expect(summary.byTask.generate).toBeCloseTo(2);
    expect(summary.spentUSD).toBeCloseTo(2);
  });

  it('rejects __proto__ task name at reserve time', () => {
    const { ledger } = createDeviceSpendLedgerHarness();
    expect(ledger.reserve('proto-task', 0.05, DAY, CONFIG, '__proto__')).toEqual({
      ok: false,
      reason: 'invalid',
    });
  });
});

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
    expect(() => structuredClone(summary)).not.toThrow();
    assertRpcPlainDeep(summary);
  });

  it('fail-closed summary (invalid config) is structured-clone plain', () => {
    const { ledger } = createDeviceSpendLedgerHarness();
    const summary = ledger.summary(DAY, BAD_CONFIG);
    expect(summary.hardCapReached).toBe(true);
    expect(() => structuredClone(summary)).not.toThrow();
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
    assertRpcPlainDeep(ledger.reconcile('a1', 0.01, 'generate'));
    assertRpcPlainDeep(ledger.reserve('a2', 0.01, DAY, BAD_CONFIG));
    assertRpcPlainDeep(ledger.reconcile('missing', 0.01));
    assertRpcPlainDeep(ledger.markUnknown('x'));
  });

  it('skips __proto__ task key in byTask without polluting the RPC object', () => {
    const state = emptyLedgerState();
    const day = state.days[DAY] ?? {
      date: DAY,
      spentMicro: 0,
      reservedMicro: 0,
      overReservationCount: 0,
      attempts: Object.create(null),
      tasks: Object.create(null),
    };
    day.tasks['__proto__'] = 1_000_000;
    day.tasks['generate'] = 2_000_000;
    state.days[DAY] = day;

    const { ledger } = createDeviceSpendLedgerHarness(state);
    const summary = ledger.summary(DAY, CONFIG);
    assertRpcPlainDeep(summary);
    expect(Object.prototype.hasOwnProperty.call(summary.byTask, '__proto__')).toBe(false);
    expect(summary.byTask.generate).toBeCloseTo(2);
    const probe: Record<string, unknown> = {};
    expect(Object.getPrototypeOf(probe)).toBe(Object.prototype);
  });

  it('reconcile with __proto__ task label does not pollute summary.byTask', () => {
    const { ledger } = createDeviceSpendLedgerHarness();
    expect(ledger.reserve('proto-task', 0.05, DAY, CONFIG, '__proto__')).toEqual({ ok: true });
    expect(ledger.reconcile('proto-task', 0.02, '__proto__')).toEqual({ ok: true });
    const summary = ledger.summary(DAY, CONFIG);
    assertRpcPlainDeep(summary);
    expect(Object.prototype.hasOwnProperty.call(summary.byTask, '__proto__')).toBe(false);
    expect(summary.spentUSD).toBeCloseTo(0.02);
  });
});

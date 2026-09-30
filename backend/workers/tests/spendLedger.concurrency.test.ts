/**
 * Spend ledger concurrency via in-memory DO stub (#14).
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createSpendLedgerMock, emptyLedger } from './helpers.js';
import { markUnknownSpend, reserveSpend } from '../src/usage.js';
import { deviceLocatorFromToken, generateDeviceToken } from '../src/tokens.js';
import type { Env, SpendConfig } from '../src/types.js';

const DAY = '2026-09-26';
const PRIOR_DAY = '2026-09-25';
const CONFIG: SpendConfig = { dailyCapUSD: 1.0, softThresholdUSD: 0.5 };
const FROZEN_NOW = new Date(`${DAY}T12:00:00.000Z`);

function envWith(mock: ReturnType<typeof createSpendLedgerMock>): Env {
  return {
    OPENROUTER_API_KEY: 'k',
    USAGE_LEDGER: emptyLedger(),
    SPEND_LEDGER: mock.namespace as Env['SPEND_LEDGER'],
  };
}

beforeEach(() => {
  vi.useFakeTimers({ now: FROZEN_NOW });
});

afterEach(() => {
  vi.useRealTimers();
});

describe('Spend ledger concurrency (in-memory stub)', () => {
  it('parallel reserves never exceed the daily cap', async () => {
    const mock = createSpendLedgerMock();
    const token = generateDeviceToken();
    const stub = mock.namespace.getByName(deviceLocatorFromToken(token)!);
    const upper = 0.12;
    const n = 40;
    const attemptIds = Array.from({ length: n }, (_, i) => `cap-a${i}`);

    const results = await Promise.all(
      attemptIds.map((id) => stub.reserve(id, upper, DAY, CONFIG))
    );

    const accepted = results.filter((r) => r.ok);
    const rejected = results.filter((r) => !r.ok && r.reason === 'hard_cap');
    expect(accepted.length).toBe(8);
    expect(accepted.length * upper).toBeLessThanOrEqual(CONFIG.dailyCapUSD);
    expect(accepted.length + rejected.length).toBe(n);

    const summary = await stub.summary(DAY, CONFIG);
    expect(summary.spentUSD + summary.reservedUSD).toBeLessThanOrEqual(CONFIG.dailyCapUSD);
    expect(summary.reservedUSD).toBeCloseTo(accepted.length * upper);
    expect(summary.hardCapReached).toBe(accepted.length * upper >= CONFIG.dailyCapUSD);
  });

  it('concurrent reserve + reconcile for one attemptId charges once', async () => {
    const mock = createSpendLedgerMock();
    const stub = mock.namespace.getByName('device-concurrent-once');
    const attemptId = 'once-1';
    const upper = 0.25;
    const actual = 0.07;

    await Promise.all([
      stub.reserve(attemptId, upper, DAY, CONFIG),
      stub.reserve(attemptId, upper, DAY, CONFIG),
      stub.reconcile(DAY, attemptId, actual),
      stub.reconcile(DAY, attemptId, actual),
      stub.reconcile(DAY, attemptId, actual),
    ]);

    const summary = await stub.summary(DAY, CONFIG);
    expect(summary.spentUSD).toBeCloseTo(actual);
    expect(summary.reservedUSD).toBeCloseTo(0);
  });

  it('markUnknown keeps funds in reservedUSD on the in-memory ledger', async () => {
    const mock = createSpendLedgerMock();
    const token = generateDeviceToken();
    const env = envWith(mock);
    const attemptId = 'unknown-mem-1';
    expect(await reserveSpend(token, attemptId, 0.33, env, DAY)).toEqual({ ok: true });
    expect(await markUnknownSpend(token, attemptId, env, 'gen-mem-1')).toEqual({ ok: true });

    const stub = mock.namespace.getByName(deviceLocatorFromToken(token)!);
    const summary = await stub.summary(DAY, CONFIG);
    expect(summary.reservedUSD).toBeCloseTo(0.33);
    expect(summary.spentUSD).toBeCloseTo(0);
    expect(summary.unresolvedAttempts).toBe(1);
  });

  it('reservation near UTC midnight lands in the requested ledger day', async () => {
    vi.setSystemTime(new Date(`${PRIOR_DAY}T23:30:00.000Z`));
    const mock = createSpendLedgerMock();
    const stub = mock.namespace.getByName('device-midnight');
    expect(await stub.reserve('midnight-1', 0.18, PRIOR_DAY, CONFIG)).toEqual({ ok: true });

    const dayBefore = await stub.summary(PRIOR_DAY, CONFIG);
    expect(dayBefore.reservedUSD).toBeCloseTo(0.18);

    vi.setSystemTime(FROZEN_NOW);
    const dayAfter = await stub.summary(DAY, CONFIG);
    expect(dayAfter.reservedUSD).toBeCloseTo(0);
    const priorAfterRoll = await stub.summary(PRIOR_DAY, CONFIG);
    expect(priorAfterRoll.reservedUSD).toBeCloseTo(0.18);
  });
});

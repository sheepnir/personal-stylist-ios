/**
 * Spend ledger concurrency on real workerd + SPEND_LEDGER DO (#14).
 */

/// <reference types="@cloudflare/vitest-plugin/types" />

import { env, runInDurableObject } from 'cloudflare:test';
import { describe, it, expect } from 'vitest';
import { markUnknownSpend, reserveSpend } from '../src/usage.js';
import { generateDeviceToken } from '../src/tokens.js';
import type { Env, SpendConfig } from '../src/types.js';

const DAY = '2026-09-26';
const CONFIG: SpendConfig = { dailyCapUSD: 1.0, softThresholdUSD: 0.5 };
const DEVICE_LOCATOR = 'a1000001-0001-4000-8000-000000000014';
const DEVICE_TOKEN = generateDeviceToken(DEVICE_LOCATOR);

function workerEnv(): Env {
  return env as Env;
}

function ledger() {
  if (!env.SPEND_LEDGER) throw new Error('SPEND_LEDGER binding missing');
  return env.SPEND_LEDGER.getByName(DEVICE_LOCATOR);
}

async function freshLedger() {
  const stub = ledger();
  await runInDurableObject(stub, async (_instance, state) => {
    await state.storage.deleteAll();
  });
  return stub;
}

describe('DeviceSpendLedger concurrency (workerd)', () => {
  it('parallel reserves never exceed the daily cap', async () => {
    const repeats = 5;
    for (let run = 0; run < repeats; run += 1) {
      const stub = await freshLedger();
      const upper = 0.12;
      const n = 40;
      const attemptIds = Array.from({ length: n }, (_, i) => `cap-run${run}-a${i}`);

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
    }
  });

  it('concurrent reserve + reconcile for one attemptId charges once', async () => {
    const repeats = 5;
    for (let run = 0; run < repeats; run += 1) {
      const stub = await freshLedger();
      const attemptId = `once-run${run}`;
      const upper = 0.25;
      const actual = 0.07;

      await Promise.all([
        stub.reserve(attemptId, upper, DAY, CONFIG),
        stub.reserve(attemptId, upper, DAY, CONFIG),
        stub.reconcile(attemptId, actual),
        stub.reconcile(attemptId, actual),
        stub.reconcile(attemptId, actual),
      ]);

      const summary = await stub.summary(DAY, CONFIG);
      expect(summary.spentUSD).toBeCloseTo(actual);
      expect(summary.reservedUSD).toBeCloseTo(0);
    }
  });

  it('markUnknown keeps funds in reservedUSD on the real DO', async () => {
    const stub = await freshLedger();
    const attemptId = 'unknown-do-1';
    const testEnv = workerEnv();
    expect(await reserveSpend(DEVICE_TOKEN, attemptId, 0.33, testEnv, DAY)).toEqual({ ok: true });
    expect(await markUnknownSpend(DEVICE_TOKEN, attemptId, testEnv, 'gen-do-1')).toEqual({
      ok: true,
    });

    const summary = await stub.summary(DAY, CONFIG);
    expect(summary.reservedUSD).toBeCloseTo(0.33);
    expect(summary.spentUSD).toBeCloseTo(0);
    expect(summary.unresolvedAttempts).toBe(1);
  });

  it('reservation near UTC midnight lands in the requested ledger day', async () => {
    const stub = await freshLedger();
    const reserveDay = '2026-09-25';
    const nextDay = '2026-09-26';
    expect(await stub.reserve('midnight-1', 0.18, reserveDay, CONFIG)).toEqual({ ok: true });

    const dayBefore = await stub.summary(reserveDay, CONFIG);
    const dayAfter = await stub.summary(nextDay, CONFIG);
    expect(dayBefore.reservedUSD).toBeCloseTo(0.18);
    expect(dayAfter.reservedUSD).toBeCloseTo(0);
  });
});

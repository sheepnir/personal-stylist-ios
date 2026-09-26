/**
 * Spend ledger wiring tests (#13-a): device id keying, legacy tokens, usage helpers.
 */

import { describe, it, expect } from 'vitest';
import {
  getSpendRecord,
  reserveSpend,
  reconcileSpend,
  markUnknownSpend,
  hashToken,
} from '../src/usage.js';
import {
  generateDeviceToken,
  deviceLocatorFromToken,
  hashToken as hashFromTokens,
} from '../src/tokens.js';
import type { Env } from '../src/types.js';
import { spendLedger, emptyLedger } from './helpers.js';

function envWithSpend(): Env {
  return {
    DEVICE_TOKEN: 'legacy-shared',
    OPENROUTER_API_KEY: 'k',
    USAGE_LEDGER: emptyLedger(),
    SPEND_LEDGER: spendLedger() as Env['SPEND_LEDGER'],
  };
}

describe('usage ↔ DeviceSpendLedger', () => {
  it('hashToken is still exported from usage.ts', async () => {
    const h = await hashToken('x');
    expect(h).toBe(await hashFromTokens('x'));
  });

  it('keys ledger by device locator (survives token rotation)', async () => {
    const env = envWithSpend();
    const locator = 'a1000001-0001-4000-8000-000000000099';
    const tokenA = generateDeviceToken(locator);
    const tokenB = generateDeviceToken(locator);

    expect(deviceLocatorFromToken(tokenA)).toBe(locator);
    expect(deviceLocatorFromToken(tokenB)).toBe(locator);

    expect(await reserveSpend(tokenA, 'attempt-1', 0.2, env)).toEqual({ ok: true });
    const afterRotate = await getSpendRecord(tokenB, env);
    expect(afterRotate.reservedUSD).toBeCloseTo(0.2);
  });

  it('legacy shared token gets no reservation', async () => {
    const env = envWithSpend();
    expect(await reserveSpend('legacy-shared', 'attempt-x', 0.5, env)).toEqual({
      ok: false,
      reason: 'no_ledger',
    });
    const record = await getSpendRecord('legacy-shared', env);
    expect(record.spentUSD).toBe(0);
    expect(record.reservedUSD).toBe(0);
  });

  it('never persists raw device tokens in ledger state', async () => {
    const env = envWithSpend();
    const token = generateDeviceToken();
    await reserveSpend(token, 'attempt-privacy', 0.05, env);
    const serialized = JSON.stringify(env);
    expect(serialized).not.toContain(token.split('.')[1]);
  });

  it('reserve + reconcile round-trip through usage helpers', async () => {
    const env = envWithSpend();
    const token = generateDeviceToken();
    expect(await reserveSpend(token, 'paid-1', 0.35, env)).toEqual({ ok: true });
    expect(await reconcileSpend(token, 'paid-1', 0.08, env)).toEqual({ ok: true });
    const record = await getSpendRecord(token, env);
    expect(record.spentUSD).toBeCloseTo(0.08);
    expect(record.reservedUSD).toBeCloseTo(0);
  });

  it('markUnknownSpend forwards attemptId and generationId without changing reservedUSD', async () => {
    const ledger = spendLedger();
    const env = envWithSpend();
    env.SPEND_LEDGER = ledger as Env['SPEND_LEDGER'];
    const token = generateDeviceToken();
    const locator = deviceLocatorFromToken(token)!;

    expect(await reserveSpend(token, 'attempt-unknown', 0.42, env)).toEqual({ ok: true });
    const before = await getSpendRecord(token, env);
    expect(before.reservedUSD).toBeCloseTo(0.42);

    expect(await markUnknownSpend(token, 'attempt-unknown', env, 'gen-forward-1')).toEqual({ ok: true });
    expect(await markUnknownSpend(token, 'attempt-unknown', env, 'gen-forward-1')).toEqual({ ok: true });

    const after = await getSpendRecord(token, env);
    expect(after.reservedUSD).toBeCloseTo(0.42);
    expect(after.spentUSD).toBeCloseTo(0);

    expect(ledger.markUnknownCalls).toEqual([
      { deviceId: locator, attemptId: 'attempt-unknown', generationId: 'gen-forward-1' },
      { deviceId: locator, attemptId: 'attempt-unknown', generationId: 'gen-forward-1' },
    ]);
  });

  it('markUnknownSpend matches reserveSpend when there is no ledger', async () => {
    const env = envWithSpend();
    const token = generateDeviceToken();
    const withoutLedger: Env = { ...env, SPEND_LEDGER: undefined };

    const reserveResult = await reserveSpend(token, 'attempt-x', 0.1, withoutLedger);
    const unknownResult = await markUnknownSpend(token, 'attempt-x', withoutLedger, 'gen-1');

    expect(unknownResult).toEqual(reserveResult);
    expect(unknownResult).toEqual({ ok: false, reason: 'no_ledger' });
  });
});

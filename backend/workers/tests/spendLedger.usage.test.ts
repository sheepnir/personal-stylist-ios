/**
 * usage.ts wiring unit tests over in-memory ledger storage (#13-a).
 * Exercises core logic via helpers.createSpendLedgerMock(); workerd / DO concurrency is #14.
 */

import { describe, it, expect } from 'vitest';
import {
  getSpendRecord,
  reserveSpend,
  reconcileSpend,
  hashToken,
  isHardCapReached,
  getUsageSummary,
} from '../src/usage.js';
import {
  generateDeviceToken,
  deviceLocatorFromToken,
  hashToken as hashFromTokens,
} from '../src/tokens.js';
import type { Env } from '../src/types.js';
import { createSpendLedgerMock, emptyLedger } from './helpers.js';

function envWithSpend(): { env: Env; dump: ReturnType<typeof createSpendLedgerMock>['dumpState'] } {
  const mock = createSpendLedgerMock();
  return {
    dump: mock.dumpState,
    env: {
      DEVICE_TOKEN: 'legacy-shared',
      OPENROUTER_API_KEY: 'k',
      USAGE_LEDGER: emptyLedger(),
      SPEND_LEDGER: mock.namespace as Env['SPEND_LEDGER'],
    },
  };
}

function envWithoutSpendBinding(): Env {
  return {
    DEVICE_TOKEN: 'legacy-shared',
    OPENROUTER_API_KEY: 'k',
    USAGE_LEDGER: emptyLedger(),
  };
}

describe('usage helpers with in-memory spend ledger', () => {
  it('hashToken is still exported from usage.ts', async () => {
    const h = await hashToken('x');
    expect(h).toBe(await hashFromTokens('x'));
  });

  it('keys ledger by device locator (survives token rotation)', async () => {
    const { env, dump: _dump } = envWithSpend();
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
    const { env } = envWithSpend();
    expect(await reserveSpend('legacy-shared', 'attempt-x', 0.5, env)).toEqual({
      ok: false,
      reason: 'no_ledger',
    });
    const record = await getSpendRecord('legacy-shared', env);
    expect(record.spentUSD).toBe(0);
    expect(record.reservedUSD).toBe(0);
    expect(await isHardCapReached('legacy-shared', env)).toBe(false);
  });

  it('fail-closed when SPEND_LEDGER is missing for a per-device token', async () => {
    const env = envWithoutSpendBinding();
    const token = generateDeviceToken();
    expect(await reserveSpend(token, 'a1', 0.1, env)).toEqual({ ok: false, reason: 'ledger_unavailable' });
    expect(await isHardCapReached(token, env)).toBe(true);
    const usage = await getUsageSummary(token, env);
    expect(usage.hardCapReached).toBe(true);
  });

  it('fail-closed when the ledger stub throws', async () => {
    const token = generateDeviceToken();
    const env: Env = {
      OPENROUTER_API_KEY: 'k',
      USAGE_LEDGER: emptyLedger(),
      SPEND_LEDGER: {
        getByName: () => {
          throw new Error('do unavailable');
        },
      } as Env['SPEND_LEDGER'],
    };
    expect(await reserveSpend(token, 'a1', 0.1, env)).toEqual({ ok: false, reason: 'ledger_unavailable' });
    expect(await isHardCapReached(token, env)).toBe(true);
  });

  it('reserve + reconcile round-trip through usage helpers with task attribution', async () => {
    const { env } = envWithSpend();
    const token = generateDeviceToken();
    expect(await reserveSpend(token, 'paid-1', 0.35, env, undefined, 'generate')).toEqual({ ok: true });
    expect(await reconcileSpend(token, 'paid-1', 0.08, env, 'generate')).toEqual({ ok: true });
    const record = await getSpendRecord(token, env);
    expect(record.spentUSD).toBeCloseTo(0.08);
    expect(record.reservedUSD).toBeCloseTo(0);
    expect(record.tasks.generate).toBeCloseTo(0.08);
  });

  it('never persists raw device tokens or token hashes in ledger storage', async () => {
    const { env, dump } = envWithSpend();
    const token = generateDeviceToken();
    const locator = deviceLocatorFromToken(token)!;
    const digest = await hashFromTokens(token);

    await reserveSpend(token, 'attempt-privacy', 0.05, env);
    await reconcileSpend(token, 'attempt-privacy', 0.04, env, 'generate');

    const persisted = JSON.stringify(dump(locator));
    expect(persisted).not.toContain(token);
    expect(persisted).not.toContain(digest);
  });
});

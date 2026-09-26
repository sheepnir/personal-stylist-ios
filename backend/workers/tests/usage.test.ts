/**
 * Usage-ledger token privacy tests (#174): the raw device token is never
 * persisted in the Durable Object ledger; summaries use device locator only.
 */

import { describe, it, expect } from 'vitest';
import {
  getSpendRecord,
  recordSpend,
  hashToken,
  reserveSpend,
  getUsageSummary,
} from '../src/usage.js';
import { SPEND_CONFIG } from '../src/types.js';
import { generateDeviceToken } from '../src/tokens.js';
import type { Env } from '../src/types.js';
import { spendLedger, emptyLedger } from './helpers.js';

function envWithSpend(): Env {
  return {
    DEVICE_TOKEN: 'unused-here',
    OPENROUTER_API_KEY: 'k',
    USAGE_LEDGER: emptyLedger(),
    SPEND_LEDGER: spendLedger() as Env['SPEND_LEDGER'],
  };
}

describe('usage ledger token privacy (#174)', () => {
  it('hashToken returns a 64-char SHA-256 hex digest', async () => {
    const h = await hashToken('sample');
    expect(h).toMatch(/^[0-9a-f]{64}$/);
  });

  it('never stores the raw device token in the spend summary', async () => {
    const env = envWithSpend();
    const token = generateDeviceToken();
    await reserveSpend(token, 'attempt-1', 0.1, env);

    const record = await getSpendRecord(token, env);
    expect((record as Record<string, unknown>).deviceToken).toBeUndefined();
    expect(JSON.stringify(record)).not.toContain(token);
  });

  it('stores tokenHash in the usage record shape and round-trips spend', async () => {
    const env = envWithSpend();
    const token = generateDeviceToken();
    const result = await recordSpend(token, 'generate', 0.25, env);
    expect(result).toEqual({ ok: true });
    const record = await getSpendRecord(token, env);

    expect(record.tokenHash).toBe(await hashToken(token));
    expect(record.spentUSD).toBeCloseTo(0.25);
  });

  it('distinct tokens do not collide on hash digests', async () => {
    const a = await hashToken('token-A');
    const b = await hashToken('token-B');
    expect(a).not.toBe(b);
  });

  it('recordSpend returns reserve failure without recording spend', async () => {
    const env = envWithSpend();
    const result = await recordSpend('legacy-shared', 'generate', 0.25, env);
    expect(result).toEqual({ ok: false, stage: 'reserve', reason: 'no_ledger' });
    const record = await getSpendRecord('legacy-shared', env);
    expect(record.spentUSD).toBe(0);
  });

  it('recordSpend returns reconcile failure after a successful reserve', async () => {
    const token = generateDeviceToken();
    const env: Env = {
      OPENROUTER_API_KEY: 'k',
      USAGE_LEDGER: emptyLedger(),
      SPEND_LEDGER: {
        getByName: () => ({
          reserve: async () => ({ ok: true }),
          reconcile: async () => ({ ok: false, reason: 'not_found' }),
          summary: async () => ({
            spentUSD: 0,
            reservedUSD: 0.1,
            softThresholdReached: false,
            hardCapReached: false,
            overReservationCount: 0,
            byTask: {},
          }),
        }),
      } as Env['SPEND_LEDGER'],
    };
    expect(await recordSpend(token, 'generate', 0.1, env)).toEqual({
      ok: false,
      stage: 'reconcile',
      reason: 'not_found',
    });
  });

  it('recordSpend returns ledger_unavailable when reserve cannot reach the DO', async () => {
    const token = generateDeviceToken();
    const env: Env = {
      OPENROUTER_API_KEY: 'k',
      USAGE_LEDGER: emptyLedger(),
    };
    expect(await recordSpend(token, 'generate', 0.1, env)).toEqual({
      ok: false,
      stage: 'reserve',
      reason: 'ledger_unavailable',
    });
  });
});

/**
 * Usage-ledger token privacy tests (#174): the raw device token is never
 * persisted in the Durable Object ledger; summaries use device locator only.
 */

import { describe, it, expect } from 'vitest';
import { getSpendRecord, recordSpend, hashToken, reserveSpend } from '../src/usage.js';
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
    await recordSpend(token, 'generate', 0.25, env);
    const record = await getSpendRecord(token, env);

    expect(record.tokenHash).toBe(await hashToken(token));
    expect(record.spentUSD).toBeCloseTo(0.25);
  });

  it('distinct tokens do not collide on hash digests', async () => {
    const a = await hashToken('token-A');
    const b = await hashToken('token-B');
    expect(a).not.toBe(b);
  });
});

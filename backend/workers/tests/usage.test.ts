/**
 * Usage-ledger token privacy tests (#174): the raw device token is never
 * persisted in the Durable Object ledger; summaries use device locator only.
 */

import { describe, it, expect } from 'vitest';
import worker from '../src/index.js';
import {
  getSpendRecord,
  recordSpend,
  hashToken,
  reserveSpend,
  markUnknownSpend,
} from '../src/usage.js';
import { generateDeviceToken, issueDeviceToken } from '../src/tokens.js';
import type { Env } from '../src/types.js';
import { spendLedger, emptyLedger, tokenRegistry } from './helpers.js';

const ctx = {} as ExecutionContext;

function envWithSpend(): Env {
  return {
    DEVICE_TOKEN: 'unused-here',
    OPENROUTER_API_KEY: 'k',
    USAGE_LEDGER: emptyLedger(),
    SPEND_LEDGER: spendLedger() as Env['SPEND_LEDGER'],
  };
}

function usageRouteEnv(): Env {
  return {
    DEVICE_TOKENS: tokenRegistry() as Env['DEVICE_TOKENS'],
    SPEND_LEDGER: spendLedger() as Env['SPEND_LEDGER'],
    OPENROUTER_API_KEY: 'k',
    USAGE_LEDGER: emptyLedger(),
    REQUEST_RATE_LIMITER: {
      limit: async () => ({ success: true }),
    } as Env['REQUEST_RATE_LIMITER'],
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

describe('GET /v1/usage unresolvedAttempts (#14)', () => {
  it('reports one unresolved attempt after markUnknownSpend', async () => {
    const env = usageRouteEnv();
    const { deviceToken } = await issueDeviceToken(env);
    await reserveSpend(deviceToken, 'usage-unknown-1', 0.15, env);
    await markUnknownSpend(deviceToken, 'usage-unknown-1', env, 'gen-usage-1');

    const response = await worker.fetch(
      new Request('http://test.com/v1/usage', {
        headers: { Authorization: `Bearer ${deviceToken}` },
      }),
      env,
      ctx
    );
    expect(response.status).toBe(200);
    const body = (await response.json()) as {
      unresolvedAttempts: number;
      reservedTodayUSD: number;
    };
    expect(body.unresolvedAttempts).toBe(1);
    expect(body.reservedTodayUSD).toBeCloseTo(0.15);
  });

  it('counts unknown on a previous UTC ledger day in unresolvedAttempts', async () => {
    const env = usageRouteEnv();
    const { deviceToken } = await issueDeviceToken(env);
    const prior = new Date();
    prior.setUTCDate(prior.getUTCDate() - 1);
    const priorDay = prior.toISOString().split('T')[0];

    await reserveSpend(deviceToken, 'usage-unknown-prior', 0.12, env, priorDay);
    await markUnknownSpend(deviceToken, 'usage-unknown-prior', env, 'gen-prior');

    const response = await worker.fetch(
      new Request('http://test.com/v1/usage', {
        headers: { Authorization: `Bearer ${deviceToken}` },
      }),
      env,
      ctx
    );
    expect(response.status).toBe(200);
    const body = (await response.json()) as {
      unresolvedAttempts: number;
      reservedTodayUSD: number;
    };
    expect(body.unresolvedAttempts).toBe(1);
    expect(body.reservedTodayUSD).toBeCloseTo(0);
  });
});

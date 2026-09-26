/**
 * Usage-ledger token privacy tests (#174): the raw device token is never
 * persisted in the Durable Object ledger; summaries use device locator only.
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import worker from '../src/index.js';
import {
  getSpendRecord,
  hashToken,
  reserveSpend,
  reconcileSpend,
  getUsageSummary,
  markUnknownSpend,
} from '../src/usage.js';
import { recordSpend } from './recordSpendHelper.js';
import { SPEND_CONFIG } from '../src/types.js';
import { generateDeviceToken, issueDeviceToken } from '../src/tokens.js';
import type { Env } from '../src/types.js';
import { spendLedger, emptyLedger, tokenRegistry } from './helpers.js';

const ctx = {} as ExecutionContext;
const DAY = '2026-09-26';
const PRIOR_DAY = '2026-09-25';
const FROZEN_NOW = new Date(`${DAY}T12:00:00.000Z`);

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
            unresolvedAttempts: 0,
            softThresholdReached: false,
            hardCapReached: false,
            overReservationCount: 0,
            byTask: {},
          }),
          unresolvedAttempts: async () => 0,
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

describe('GET /v1/usage unresolvedAttempts (#14)', () => {
  beforeEach(() => {
    vi.useFakeTimers({ now: FROZEN_NOW });
  });

  afterEach(() => {
    vi.useRealTimers();
  });

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

    vi.setSystemTime(new Date(`${PRIOR_DAY}T12:00:00.000Z`));
    await reserveSpend(deviceToken, 'usage-unknown-prior', 0.12, env, PRIOR_DAY);
    await markUnknownSpend(deviceToken, 'usage-unknown-prior', env, 'gen-prior');
    vi.setSystemTime(new Date(`${DAY}T11:00:00.000Z`));

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

/**
 * GET /v1/models and usage ledger day reset fields (#12).
 */

import { describe, it, expect, afterEach } from 'vitest';
import worker from '../src/index.js';
import {
  ledgerDayEndsAtUtc,
  setUsageClockForTests,
  getUsageSummary,
} from '../src/usage.js';
import type { Env } from '../src/types.js';
import { emptyLedger, spendLedger } from './helpers.js';
import { RATE_LIMIT_MAX } from '../src/validation.js';

const ctx = {} as ExecutionContext;
const TOKEN = 'test-token-123';

function env(overrides: Partial<Env> = {}): Env {
  let requests = 0;
  return {
    REQUEST_RATE_LIMITER: {
      limit: async () => ({ success: ++requests <= RATE_LIMIT_MAX }),
    },
    DEVICE_TOKEN: TOKEN,
    OPENROUTER_API_KEY: 'k',
    USAGE_LEDGER: emptyLedger(),
    SPEND_LEDGER: spendLedger() as Env['SPEND_LEDGER'],
    ...overrides,
  };
}

describe('ledgerDayEndsAtUtc', () => {
  afterEach(() => {
    setUsageClockForTests(null);
  });

  it('at 23:59:59.999Z returns the next UTC midnight', () => {
    const end = ledgerDayEndsAtUtc(new Date('2026-03-15T23:59:59.999Z'));
    expect(end).toBe('2026-03-16T00:00:00.000Z');
  });

  it('at 00:00:00.000Z returns that day’s next UTC midnight', () => {
    const end = ledgerDayEndsAtUtc(new Date('2026-03-16T00:00:00.000Z'));
    expect(end).toBe('2026-03-17T00:00:00.000Z');
  });

  it('is independent of process TZ when the clock is injected', () => {
    const prior = process.env.TZ;
    process.env.TZ = 'America/Los_Angeles';
    try {
      setUsageClockForTests(() => new Date('2026-06-01T07:00:00.000Z'));
      expect(ledgerDayEndsAtUtc()).toBe('2026-06-02T00:00:00.000Z');
    } finally {
      if (prior === undefined) delete process.env.TZ;
      else process.env.TZ = prior;
    }
  });
});

describe('GET /v1/usage resetsAt', () => {
  afterEach(() => {
    setUsageClockForTests(null);
  });

  it('sets resetsAt equal to ledgerDayEndsAt', async () => {
    setUsageClockForTests(() => new Date('2026-09-26T15:00:00.000Z'));
    const summary = await getUsageSummary(TOKEN, env());
    expect(summary.ledgerDayEndsAt).toBe('2026-09-27T00:00:00.000Z');
    expect(summary.resetsAt).toBe(summary.ledgerDayEndsAt);
  });

  it('uses one UTC day boundary captured before ledger I/O even if the clock crosses midnight', async () => {
    let clockCalls = 0;
    setUsageClockForTests(() => {
      clockCalls += 1;
      if (clockCalls === 1) {
        return new Date('2026-03-15T23:59:59.999Z');
      }
      return new Date('2026-03-16T00:00:00.001Z');
    });

    const summary = await getUsageSummary(TOKEN, env());
    expect(summary.ledgerDayEndsAt).toBe('2026-03-16T00:00:00.000Z');
    expect(summary.resetsAt).toBe('2026-03-16T00:00:00.000Z');
    // getUsageSummary must not re-read the clock during ledger I/O (would see 2026-03-16).
    expect(clockCalls).toBe(1);
  });
});

describe('GET /v1/models', () => {
  it('returns 401 without Authorization', async () => {
    const res = await worker.fetch(new Request('http://test.com/v1/models'), env(), ctx);
    expect(res.status).toBe(401);
  });

  it('returns 200 with schema fields and policyVersion null', async () => {
    const res = await worker.fetch(
      new Request('http://test.com/v1/models', {
        headers: { Authorization: `Bearer ${TOKEN}` },
      }),
      env({ STYLIST_PRIMARY_MODEL: 'mock/stylist-v0' }),
      ctx
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as Record<string, unknown>;
    expect(body.policyVersion).toBeNull();
    expect(body.promptVersion).toBe('none');
    expect(body.primary).toMatchObject({ slug: 'mock/stylist-v0' });
    expect(body.dataPolicy).toMatchObject({
      excludesTrainingProviders: true,
      verifiedOn: null,
    });
    const raw = JSON.stringify(body);
    expect(raw).not.toContain('OPENROUTER');
    expect(raw).not.toMatch(/STYLIST_/);
  });

  it('serves null primary when env is unset', async () => {
    const res = await worker.fetch(
      new Request('http://test.com/v1/models', {
        headers: { Authorization: `Bearer ${TOKEN}` },
      }),
      env(),
      ctx
    );
    const body = (await res.json()) as { primary: unknown };
    expect(body.primary).toBeNull();
  });
});

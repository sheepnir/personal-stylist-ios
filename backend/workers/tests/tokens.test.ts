import { tokenRegistry, spendLedger, emptyLedger } from './helpers.js';
/**
 * Device-token lifecycle tests (D-46 / #169).
 */

import { describe, it, expect } from 'vitest';
import worker from '../src/index.js';
import type { Env } from '../src/types.js';

const ctx = {} as ExecutionContext;
const ENROLLMENT = 'enrollment-secret-xyz';
const LEGACY = 'legacy-shared-token';

class MemoryKV {
  store = new Map<string, string>();
  async get(key: string, type?: 'json'): Promise<unknown> {
    const raw = this.store.get(key);
    if (raw === undefined) return null;
    return type === 'json' ? JSON.parse(raw) : raw;
  }
  async put(key: string, value: string): Promise<void> {
    this.store.set(key, value);
  }
}

function env(kv = new MemoryKV()): Env {
  let requests = 0;
  return {
    DEVICE_TOKENS: tokenRegistry() as Env["DEVICE_TOKENS"],
    SPEND_LEDGER: spendLedger() as Env['SPEND_LEDGER'],
    DEVICE_TOKEN: LEGACY,
    ENROLLMENT_SECRET: ENROLLMENT,
    OPENROUTER_API_KEY: 'k',
    USAGE_LEDGER: kv as unknown as KVNamespace,
    REQUEST_RATE_LIMITER: {
      limit: async () => ({ success: ++requests <= 60 }),
    } as Env['REQUEST_RATE_LIMITER'],
  };
}

describe('device token issuance / rotation / revocation (D-46)', () => {
  it('issues a token with the enrollment secret and rejects content without it', async () => {
    const e = env();
    const issueReq = new Request('http://test.com/v1/auth/device', {
      method: 'POST',
      headers: { Authorization: `Bearer ${ENROLLMENT}` },
    });
    const issued = await worker.fetch(issueReq, e, ctx);
    expect(issued.status).toBe(201);
    const body = (await issued.json()) as { deviceToken?: string };
    expect(typeof body.deviceToken).toBe('string');
    expect(body.deviceToken!.length).toBeGreaterThan(20);

    const usageOk = await worker.fetch(
      new Request('http://test.com/v1/usage', {
        headers: { Authorization: `Bearer ${body.deviceToken}` },
      }),
      e,
      ctx
    );
    expect(usageOk.status).toBe(200);
  });

  it('rejects issuance with a wrong enrollment secret', async () => {
    const res = await worker.fetch(
      new Request('http://test.com/v1/auth/device', {
        method: 'POST',
        headers: { Authorization: 'Bearer wrong' },
      }),
      env(),
      ctx
    );
    expect(res.status).toBe(401);
  });

  it('revokes a device token so it can no longer call content endpoints', async () => {
    const e = env();
    const issued = await worker.fetch(
      new Request('http://test.com/v1/auth/device', {
        method: 'POST',
        headers: { Authorization: `Bearer ${ENROLLMENT}` },
      }),
      e,
      ctx
    );
    const { deviceToken } = (await issued.json()) as { deviceToken: string };

    const revoked = await worker.fetch(
      new Request('http://test.com/v1/auth/device/revoke', {
        method: 'POST',
        headers: { Authorization: `Bearer ${deviceToken}` },
      }),
      e,
      ctx
    );
    expect(revoked.status).toBe(204);

    const denied = await worker.fetch(
      new Request('http://test.com/v1/usage', {
        headers: { Authorization: `Bearer ${deviceToken}` },
      }),
      e,
      ctx
    );
    expect(denied.status).toBe(401);
  });

  it('rotates a device token: old fails, new succeeds', async () => {
    const e = env();
    const issued = await worker.fetch(
      new Request('http://test.com/v1/auth/device', {
        method: 'POST',
        headers: { Authorization: `Bearer ${ENROLLMENT}` },
      }),
      e,
      ctx
    );
    const { deviceToken: oldToken } = (await issued.json()) as { deviceToken: string };

    const rotated = await worker.fetch(
      new Request('http://test.com/v1/auth/device/rotate', {
        method: 'POST',
        headers: { Authorization: `Bearer ${oldToken}` },
      }),
      e,
      ctx
    );
    expect(rotated.status).toBe(200);
    const { deviceToken: newToken } = (await rotated.json()) as { deviceToken: string };
    expect(newToken).not.toBe(oldToken);

    expect(
      (
        await worker.fetch(
          new Request('http://test.com/v1/usage', {
            headers: { Authorization: `Bearer ${oldToken}` },
          }),
          e,
          ctx
        )
      ).status
    ).toBe(401);

    expect(
      (
        await worker.fetch(
          new Request('http://test.com/v1/usage', {
            headers: { Authorization: `Bearer ${newToken}` },
          }),
          e,
          ctx
        )
      ).status
    ).toBe(200);
  });

  it('still accepts the legacy shared DEVICE_TOKEN during migration', async () => {
    const res = await worker.fetch(
      new Request('http://test.com/v1/usage', {
        headers: { Authorization: `Bearer ${LEGACY}` },
      }),
      env(),
      ctx
    );
    expect(res.status).toBe(200);
  });

  it('does not treat the enrollment secret as a content credential', async () => {
    const res = await worker.fetch(
      new Request('http://test.com/v1/usage', {
        headers: { Authorization: `Bearer ${ENROLLMENT}` },
      }),
      env(),
      ctx
    );
    expect(res.status).toBe(401);
  });
});

// Regressions for stale-read and concurrent-rotation blockers repaired by D-47.
import { issueDeviceToken, rotateDeviceToken } from '../src/tokens.js';

describe('review regressions', () => {
  it('marks issued credentials no-store and throttles enrollment', async () => {
    const e = env();
    e.REQUEST_RATE_LIMITER = { limit: async () => ({ success: false }) };
    const request = () => new Request('http://test.com/v1/auth/device', {
      method: 'POST', headers: { Authorization: `Bearer ${ENROLLMENT}` },
    });
    expect((await worker.fetch(request(), e, ctx)).status).toBe(429);
    e.REQUEST_RATE_LIMITER = { limit: async () => ({ success: true }) };
    const response = await worker.fetch(request(), e, ctx);
    expect(response.status).toBe(201);
    expect(response.headers.get('Cache-Control')).toBe('no-store');
  });

  it('returns a controlled fail-closed response on registry failure', async () => {
    const e = env();
    const token = (await issueDeviceToken(e)).deviceToken;
    e.DEVICE_TOKENS = { getByName: () => { throw new Error('offline'); } } as unknown as Env['DEVICE_TOKENS'];
    const response = await worker.fetch(new Request('http://test.com/v1/usage', {
      headers: { Authorization: `Bearer ${token}` },
    }), e, ctx);
    expect(response.status).toBe(503);
  });

  it('D-46: revoked tokens must fail even at a location with a stale KV read', async () => {
    const kv = new MemoryKV();
    const e = env(kv);
    const issued = await issueDeviceToken(e);
    const stale = new Map(kv.store);
    const request = (path: string, method = 'GET') => new Request(`http://test.com${path}`, {
      method, headers: { Authorization: `Bearer ${issued.deviceToken}` },
    });
    expect((await worker.fetch(request('/v1/auth/device/revoke', 'POST'), e, ctx)).status).toBe(204);
    const remote = env();
    remote.DEVICE_TOKENS = e.DEVICE_TOKENS;
    remote.USAGE_LEDGER = { get: async (key: string, type?: string) => {
      const raw = stale.get(key);
      return raw === undefined ? null : type === 'json' ? JSON.parse(raw) : raw;
    } } as unknown as KVNamespace;
    expect((await worker.fetch(request('/v1/usage'), remote, ctx)).status).toBe(401);
  });

  it('D-46: concurrent rotation must not issue multiple successors', async () => {
    const e = env();
    const original = await issueDeviceToken(e);
    const results = await Promise.all([
      rotateDeviceToken(original.deviceToken, e),
      rotateDeviceToken(original.deviceToken, e),
    ]);
    expect(results.filter(Boolean)).toHaveLength(1);
  });
});

import { describe, expect, it, vi } from 'vitest';
import worker from '../src/index.js';
import type { Env } from '../src/types.js';
import { GLOBAL_LEDGER_NAME } from '../src/paidSelection.js';
import { issueDeviceToken } from '../src/tokens.js';
import { emptyLedger, tokenRegistry } from './helpers.js';
import { MAX_BODY_BYTES } from '../src/validation.js';

const CONTROL = 'synthetic-control-secret';
const DEVICE = 'synthetic-legacy-device-secret';
const ENROLLMENT = 'synthetic-enrollment-secret';
const ctx = { waitUntil: vi.fn(), passThroughOnException: vi.fn() } as unknown as ExecutionContext;
function setup() {
  const setProviderEnabled = vi.fn().mockResolvedValue(undefined);
  const getByName = vi.fn().mockReturnValue({ setProviderEnabled });
  const env: Env = {
    PROVIDER_CONTROL_SECRET: CONTROL, DEVICE_TOKEN: DEVICE, ENROLLMENT_SECRET: ENROLLMENT,
    DEVICE_TOKENS: tokenRegistry(), USAGE_LEDGER: emptyLedger(),
    REQUEST_RATE_LIMITER: { limit: async () => ({ success: true }) },
    SPEND_LEDGER: { getByName } as unknown as NonNullable<Env['SPEND_LEDGER']>,
  };
  const request = (authorization: string | undefined, body = '{"enabled":true}', method = 'POST') => {
    const headers: Record<string, string> = { 'Content-Type': 'application/json' };
    if (authorization !== undefined) headers.Authorization = authorization;
    return worker.fetch(new Request('https://example.invalid/v1/admin/provider-switch', {
      method, headers, ...(method === 'GET' ? {} : { body }),
    }), env, ctx);
  };
  return { env, setProviderEnabled, getByName, request };
}

describe('admin provider switch credential boundary', () => {
  it.each([undefined, 'Bearer wrong-secret', `Bearer ${DEVICE}`, `Bearer ${ENROLLMENT}`,
    `Basic ${CONTROL}`, `bearer ${CONTROL}`, CONTROL])('rejects %s without ledger access', async authorization => {
    const s = setup();
    expect((await s.request(authorization)).status).toBe(401);
    expect(s.getByName).not.toHaveBeenCalled();
    expect(s.setProviderEnabled).not.toHaveBeenCalled();
  });

  it('rejects an active per-device token that authenticates a content endpoint', async () => {
    const s = setup();
    const { deviceToken } = await issueDeviceToken(s.env);
    const content = await worker.fetch(new Request('https://example.invalid/v1/models', {
      headers: { Authorization: `Bearer ${deviceToken}` },
    }), s.env, ctx);
    expect(content.status).toBe(200);
    expect((await s.request(`Bearer ${deviceToken}`)).status).toBe(401);
    expect(s.getByName).not.toHaveBeenCalled();
    expect(s.setProviderEnabled).not.toHaveBeenCalled();
  });

  it.each([undefined, ''])('fails closed when control secret is %s', async secret => {
    const s = setup();
    s.env.PROVIDER_CONTROL_SECRET = secret;
    expect((await s.request(`Bearer ${CONTROL}`)).status).toBe(401);
    expect(s.getByName).not.toHaveBeenCalled();
  });

  it('enables and disables only the global ledger using the separate control secret', async () => {
    const s = setup();
    for (const enabled of [true, false]) {
      expect((await s.request(`Bearer ${CONTROL}`, JSON.stringify({ enabled }))).status).toBe(204);
    }
    expect(s.getByName.mock.calls).toEqual([[GLOBAL_LEDGER_NAME], [GLOBAL_LEDGER_NAME]]);
    expect(s.setProviderEnabled.mock.calls).toEqual([[true], [false]]);
  });

  it('does not accept the control secret as a content credential', async () => {
    const s = setup();
    const response = await worker.fetch(new Request('https://example.invalid/v1/models', {
      headers: { Authorization: `Bearer ${CONTROL}` },
    }), s.env, ctx);
    expect(response.status).toBe(401);
    expect(s.getByName).not.toHaveBeenCalled();
  });

  it.each(['', '{', 'null', '[]', 'true', '{}', '{"enabled":"true"}', '{"enabled":1}', '{"enabled":null}'])
    ('rejects invalid body %s without mutation', async body => {
      const s = setup();
      expect((await s.request(`Bearer ${CONTROL}`, body)).status).toBe(400);
      expect(s.getByName).not.toHaveBeenCalled();
      expect(s.setProviderEnabled).not.toHaveBeenCalled();
    });

  it('rejects oversized body without mutation', async () => {
    const s = setup();
    expect((await s.request(`Bearer ${CONTROL}`, JSON.stringify({ enabled: true, padding: 'x'.repeat(MAX_BODY_BYTES) }))).status).toBe(413);
    expect(s.getByName).not.toHaveBeenCalled();
  });

  it('fails when the ledger binding is unavailable', async () => {
    const s = setup();
    s.env.SPEND_LEDGER = undefined;
    expect((await s.request(`Bearer ${CONTROL}`)).status).toBe(503);
    expect(s.setProviderEnabled).not.toHaveBeenCalled();
  });

  it('reports failure when the ledger rejects the mutation', async () => {
    const s = setup();
    s.setProviderEnabled.mockRejectedValue(new Error('synthetic storage failure'));
    expect((await s.request(`Bearer ${CONTROL}`)).status).toBe(503);
    expect(s.setProviderEnabled).toHaveBeenCalledExactlyOnceWith(true);
  });

  it('rejects GET without consulting the ledger', async () => {
    const s = setup();
    const response = await s.request(`Bearer ${CONTROL}`, undefined, 'GET');
    expect(response.status).toBe(405);
    expect(response.headers.get('Allow')).toBe('POST');
    expect(s.getByName).not.toHaveBeenCalled();
  });
});

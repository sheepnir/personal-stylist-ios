/**
 * Auth hardening tests: constant-time comparison (#177) and empty-token /
 * empty-secret fail-closed behavior (#179).
 */

import { describe, it, expect } from 'vitest';
import { authenticate } from '../src/auth.js';
import type { Env } from '../src/types.js';
import { emptyLedger } from './helpers.js';

function envWith(token: string): Env {
  return {
    DEVICE_TOKEN: token,
    OPENROUTER_API_KEY: 'test-key',
    USAGE_LEDGER: emptyLedger(),
  };
}

function bearer(token: string): Request {
  return new Request('http://test.com/v1/usage', {
    headers: { Authorization: `Bearer ${token}` },
  });
}

describe('authenticate — empty token / secret fail closed (#179)', () => {
  it('rejects an empty presented token even if the secret is also empty', async () => {
    const result = await authenticate(bearer(''), envWith(''));
    expect(result).toBeInstanceOf(Response);
    if (result instanceof Response) expect(result.status).toBe(401);
  });

  it('rejects any token when the server secret is empty (misconfiguration)', async () => {
    const result = await authenticate(bearer('anything'), envWith(''));
    expect(result).toBeInstanceOf(Response);
    if (result instanceof Response) expect(result.status).toBe(401);
  });

  it('rejects an empty presented token when the secret is set', async () => {
    const result = await authenticate(bearer(''), envWith('real-token'));
    expect(result).toBeInstanceOf(Response);
    if (result instanceof Response) expect(result.status).toBe(401);
  });
});

describe('authenticate — constant-time compare correctness (#177)', () => {
  it('accepts the correct token', async () => {
    const result = await authenticate(bearer('correct-horse'), envWith('correct-horse'));
    expect(result).not.toBeInstanceOf(Response);
    if (!(result instanceof Response)) expect(result.deviceToken).toBe('correct-horse');
  });

  it('rejects a token of a different length (no early-return length leak)', async () => {
    const result = await authenticate(bearer('short'), envWith('a-much-longer-secret-token'));
    expect(result).toBeInstanceOf(Response);
    if (result instanceof Response) expect(result.status).toBe(401);
  });

  it('rejects a same-length but different token', async () => {
    const result = await authenticate(bearer('abcdef'), envWith('abcxyz'));
    expect(result).toBeInstanceOf(Response);
    if (result instanceof Response) expect(result.status).toBe(401);
  });
});

/**
 * CORS tests: no wildcard Access-Control-Allow-Origin (#178); origins are only
 * reflected when explicitly allowlisted via ALLOWED_ORIGINS.
 */

import { describe, it, expect } from 'vitest';
import worker from '../src/index.js';
import type { Env } from '../src/types.js';

const ctx = {} as ExecutionContext;

function envWith(allowed?: string): Env {
  return {
    DEVICE_TOKEN: 'test-token-123',
    OPENROUTER_API_KEY: 'test-key',
    USAGE_LEDGER: {} as KVNamespace,
    ALLOWED_ORIGINS: allowed,
  };
}

describe('CORS Access-Control-Allow-Origin (#178)', () => {
  it('never returns a wildcard origin on health', async () => {
    const res = await worker.fetch(new Request('http://test.com/health'), envWith(), ctx);
    expect(res.headers.get('Access-Control-Allow-Origin')).not.toBe('*');
  });

  it('omits ACAO when no allowlist is configured, even with an Origin', async () => {
    const req = new Request('http://test.com/health', { headers: { Origin: 'https://evil.example' } });
    const res = await worker.fetch(req, envWith(), ctx);
    expect(res.headers.get('Access-Control-Allow-Origin')).toBeNull();
  });

  it('does not reflect a non-allowlisted origin', async () => {
    const req = new Request('http://test.com/health', { headers: { Origin: 'https://evil.example' } });
    const res = await worker.fetch(req, envWith('https://app.example'), ctx);
    expect(res.headers.get('Access-Control-Allow-Origin')).toBeNull();
  });

  it('reflects an allowlisted origin exactly', async () => {
    const req = new Request('http://test.com/health', { headers: { Origin: 'https://app.example' } });
    const res = await worker.fetch(req, envWith('https://app.example, https://other.example'), ctx);
    expect(res.headers.get('Access-Control-Allow-Origin')).toBe('https://app.example');
    expect(res.headers.get('Vary')).toContain('Origin');
  });

  it('handles OPTIONS preflight without a wildcard', async () => {
    const req = new Request('http://test.com/v1/outfit/generate', {
      method: 'OPTIONS',
      headers: { Origin: 'https://app.example' },
    });
    const res = await worker.fetch(req, envWith('https://app.example'), ctx);
    expect(res.status).toBe(204);
    expect(res.headers.get('Access-Control-Allow-Origin')).toBe('https://app.example');
  });
});

/**
 * Usage-ledger token privacy tests (#174): the raw device token is never
 * persisted, and the KV key uses a cryptographic (SHA-256) hash.
 */

import { describe, it, expect } from 'vitest';
import { getSpendRecord, recordSpend, hashToken } from '../src/usage.js';
import type { Env } from '../src/types.js';

class MemoryKV {
  store = new Map<string, string>();
  async get(key: string, _type?: 'json'): Promise<unknown> {
    const raw = this.store.get(key);
    if (raw === undefined) return null;
    return _type === 'json' ? JSON.parse(raw) : raw;
  }
  async put(key: string, value: string): Promise<void> {
    this.store.set(key, value);
  }
}

function envWithKV(kv: MemoryKV): Env {
  return {
    DEVICE_TOKEN: 'unused-here',
    OPENROUTER_API_KEY: 'k',
    USAGE_LEDGER: kv as unknown as KVNamespace,
  };
}

const TOKEN = 'device-token-abc-123';

describe('usage ledger token privacy (#174)', () => {
  it('hashToken returns a 64-char SHA-256 hex digest', async () => {
    const h = await hashToken(TOKEN);
    expect(h).toMatch(/^[0-9a-f]{64}$/);
  });

  it('never stores the raw device token in the ledger value', async () => {
    const kv = new MemoryKV();
    await recordSpend(TOKEN, 'generate', 0.1, envWithKV(kv));

    const values = [...kv.store.values()].join('\n');
    expect(values).not.toContain(TOKEN);

    const keys = [...kv.store.keys()];
    expect(keys.length).toBe(1);
    expect(keys[0]).not.toContain(TOKEN);
    // Key format: spend:<64-hex>:<YYYY-MM-DD>
    expect(keys[0]).toMatch(/^spend:[0-9a-f]{64}:\d{4}-\d{2}-\d{2}$/);
  });

  it('stores tokenHash and round-trips spend', async () => {
    const kv = new MemoryKV();
    const env = envWithKV(kv);
    await recordSpend(TOKEN, 'generate', 0.25, env);
    const record = await getSpendRecord(TOKEN, env);

    expect(record.tokenHash).toBe(await hashToken(TOKEN));
    expect(record.spentUSD).toBeCloseTo(0.25);
    expect((record as Record<string, unknown>).deviceToken).toBeUndefined();
  });

  it('distinct tokens do not collide on the same KV bucket', async () => {
    const a = await hashToken('token-A');
    const b = await hashToken('token-B');
    expect(a).not.toBe(b);
  });
});

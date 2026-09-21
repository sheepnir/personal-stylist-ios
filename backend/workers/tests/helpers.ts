/**
 * Shared in-memory KV for Workers unit tests.
 */

export class MemoryKV {
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

export function emptyLedger(): KVNamespace {
  return new MemoryKV() as unknown as KVNamespace;
}

export function tokenRegistry(): DurableObjectNamespace {
  const devices = new Map<string, { hash: string; issuedAt: string; status: string }>();
  return { getByName: (id: string) => ({
    lookup: async (hash: string) => {
      const value = devices.get(id);
      return value?.hash === hash ? { status: value.status, issuedAt: value.issuedAt } : null;
    },
    issue: async (hash: string, issuedAt: string) => {
      if (devices.has(id)) return false;
      devices.set(id, { hash, issuedAt, status: 'active' }); return true;
    },
    revoke: async (hash: string) => {
      const value = devices.get(id);
      if (value?.hash !== hash || value.status !== 'active') return false;
      value.status = 'revoked'; return true;
    },
    rotate: async (oldHash: string, hash: string, issuedAt: string) => {
      const value = devices.get(id);
      if (value?.hash !== oldHash || value.status !== 'active') return false;
      devices.set(id, { hash, issuedAt, status: 'active' }); return true;
    },
  }) } as unknown as DurableObjectNamespace;
}

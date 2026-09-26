/**
 * Persisted bucket validation and storage-key safety.
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import {
  emptyLedgerState,
  isDayStorageCorrupt,
  reserveAttempt,
  MAX_ATTEMPT_USD,
} from '../src/ledgerCore.js';
import {
  bucketStorageKey,
  loadLedgerFromStorage,
  parseBucketStorageKey,
  validateStoredDayBucket,
} from '../src/ledgerBucketStorage.js';

const DAY = '2026-09-26';
const CONFIG = { dailyCapUSD: 10_000, softThresholdUSD: 5000 };
const NOW = new Date(`${DAY}T12:00:00.000Z`);

function memoryKv(initial: Record<string, unknown> = {}) {
  const store = new Map<string, unknown>(Object.entries(initial));
  return {
    get: <T>(key: string) => store.get(key) as T | undefined,
    put: (key: string, value: unknown) => {
      store.set(key, value);
    },
    delete: (key: string) => {
      store.delete(key);
    },
    list: (options?: { prefix?: string }) => {
      const prefix = options?.prefix ?? '';
      const entries: [string, unknown][] = [];
      for (const [name, value] of store) {
        if (name.startsWith(prefix)) {
          entries.push([name, value]);
        }
      }
      return entries;
    },
  };
}

describe('validateStoredDayBucket', () => {
  const validBase = {
    s: 0,
    r: 0,
    o: 0,
    a: {},
    k: {},
  };

  it('rejects negative spent micro (s)', () => {
    expect(validateStoredDayBucket({ ...validBase, s: -1 })).toBeNull();
  });

  it('rejects fractional spent micro', () => {
    expect(validateStoredDayBucket({ ...validBase, s: 1.5 })).toBeNull();
  });

  it('rejects unsafe integer spent micro', () => {
    expect(validateStoredDayBucket({ ...validBase, s: Number.MAX_SAFE_INTEGER + 1 })).toBeNull();
  });

  it('rejects unknown attempt state code', () => {
    expect(
      validateStoredDayBucket({
        ...validBase,
        a: {
          ok: { u: 1, t: 'generate', S: 9, c: 0 },
        },
      })
    ).toBeNull();
  });
});

describe('loadLedgerFromStorage fail-closed', () => {
  beforeEach(() => {
    vi.useFakeTimers({ now: NOW });
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it('marks a malformed bucket corrupt and refuses new reserves', () => {
    const kv = memoryKv({
      [bucketStorageKey(DAY)]: { s: -1, r: 0, o: 0, a: {}, k: {} },
    });
    const state = loadLedgerFromStorage(kv);
    expect(isDayStorageCorrupt(state, DAY)).toBe(true);
    expect(state.days[DAY]).toBeUndefined();
    expect(reserveAttempt(state, 'new', 0.1, DAY, CONFIG, 'generate', NOW)).toEqual({
      ok: false,
      reason: 'storage_error',
    });
  });

  it('ignores bucket:__proto__ keys without polluting state.days', () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const kv = memoryKv({
      'bucket:__proto__': { s: 0, r: 0, o: 0, a: {}, k: {} },
      [bucketStorageKey(DAY)]: { s: 0, r: 0, o: 0, a: {}, k: {} },
    });
    const state = loadLedgerFromStorage(kv);
    expect(parseBucketStorageKey('bucket:__proto__')).toBeNull();
    expect(state.days.__proto__).toBeUndefined();
    expect(Object.hasOwn(state.days, '__proto__')).toBe(false);
    expect(warn).toHaveBeenCalled();
    warn.mockRestore();
  });
});

describe('MAX_ATTEMPT_USD bounds', () => {
  it('rejects reserve above the per-attempt ceiling', () => {
    const state = emptyLedgerState();
    expect(reserveAttempt(state, 'big', MAX_ATTEMPT_USD + 0.01, DAY, CONFIG, 'generate', NOW)).toEqual({
      ok: false,
      reason: 'invalid',
    });
    expect(reserveAttempt(state, 'ok', MAX_ATTEMPT_USD, DAY, CONFIG, 'generate', NOW)).toEqual({
      ok: true,
    });
  });
});

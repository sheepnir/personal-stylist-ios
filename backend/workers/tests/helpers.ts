/**
 * Shared in-memory KV for Workers unit tests.
 */

import {
  ageLedger,
  emptyLedgerState,
  reconcileAttempt,
  removeEmptyDayBucket,
  reserveAttempt,
  summarizeDay,
  type LedgerState,
} from '../src/ledgerCore.js';
import type { SpendConfig } from '../src/types.js';
import { bucketStorageKey, encodeDayForStorage, loadLedgerFromStorage } from '../src/ledgerBucketStorage.js';
import { DeviceSpendLedger } from '../src/spendLedger.js';

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

/** In-memory per-device spend ledger stub (same API as DeviceSpendLedger). */
export interface SpendLedgerMock {
  namespace: DurableObjectNamespace;
  dumpState: (deviceId: string) => LedgerState;
}

export function createSpendLedgerMock(): SpendLedgerMock {
  const byDevice = new Map<string, LedgerState>();

  const stateFor = (deviceId: string): LedgerState => {
    let state = byDevice.get(deviceId);
    if (!state) {
      state = emptyLedgerState();
      byDevice.set(deviceId, state);
    }
    return state;
  };

  const namespace = {
    getByName: (deviceId: string) => ({
      reserve: async (
        attemptId: string,
        upperBoundUSD: number,
        day: string,
        config: SpendConfig,
        task = 'unknown'
      ) => {
        const state = stateFor(deviceId);
        ageLedger(state, new Date());
        const result = reserveAttempt(state, attemptId, upperBoundUSD, day, config, task);
        if (!result.ok) {
          removeEmptyDayBucket(state, day);
        }
        return result;
      },
      reconcile: async (day: string, attemptId: string, actualUSD: number, task?: string) => {
        const state = stateFor(deviceId);
        ageLedger(state, new Date());
        return reconcileAttempt(state, day, attemptId, actualUSD, task);
      },
      summary: async (day: string, config: SpendConfig) => {
        const state = stateFor(deviceId);
        ageLedger(state, new Date());
        return summarizeDay(state, day, config);
      },
      markUnknown: async () => ({ ok: false }),
    }),
  } as unknown as DurableObjectNamespace;

  return {
    namespace,
    dumpState: (deviceId: string) => structuredClone(byDevice.get(deviceId) ?? emptyLedgerState()),
  };
}

export function spendLedger(): DurableObjectNamespace {
  return createSpendLedgerMock().namespace;
}

/** Fake DO storage for unit-testing {@link DeviceSpendLedger} persist + RPC returns. */
export function createDeviceSpendLedgerHarness(
  initialState?: LedgerState,
  options?: { maxValueBytes?: number; initialKv?: Record<string, unknown> }
): {
  ledger: DeviceSpendLedger;
  putCount: () => number;
  resetPutCount: () => void;
  getStoredState: () => LedgerState | undefined;
  kvHas: (key: string) => boolean;
} {
  const kvStore = new Map<string, unknown>();
  const putLog: unknown[] = [];
  if (initialState) {
    for (const [day, record] of Object.entries(initialState.days)) {
      kvStore.set(bucketStorageKey(day), encodeDayForStorage(structuredClone(record)));
    }
  }
  if (options?.initialKv) {
    for (const [key, value] of Object.entries(options.initialKv)) {
      kvStore.set(key, value);
    }
  }
  const maxValueBytes = options?.maxValueBytes;
  const storage = {
    kv: {
      get: <T>(key: string): T | undefined => kvStore.get(key) as T | undefined,
      put: (key: string, value: unknown) => {
        const bytes = new TextEncoder().encode(JSON.stringify(value)).length;
        if (maxValueBytes !== undefined && bytes > maxValueBytes) {
          throw new Error('SQLITE_TOOBIG');
        }
        putLog.push(value);
        kvStore.set(key, value);
      },
      delete: (key: string) => {
        kvStore.delete(key);
      },
      list: (options?: { prefix?: string }) => {
        const prefix = options?.prefix ?? '';
        const entries: [string, unknown][] = [];
        for (const [name, value] of kvStore) {
          if (name.startsWith(prefix)) {
            entries.push([name, value]);
          }
        }
        return entries;
      },
    },
    transactionSync: <T>(fn: () => T): T => fn(),
  };
  const ledger = new DeviceSpendLedger({ storage } as DurableObjectState, {} as import('../src/types.js').Env);
  return {
    ledger,
    putCount: () => putLog.length,
    resetPutCount: () => {
      putLog.length = 0;
    },
    getStoredState: () => {
      const state = loadLedgerFromStorage(storage.kv);
      const hasDays = Object.keys(state.days).length > 0;
      const hasCorrupt =
        state.corruptDays !== undefined && Object.keys(state.corruptDays).length > 0;
      const legacyBlocked = state.legacyMonolithPresent === true;
      return hasDays || hasCorrupt || legacyBlocked ? state : undefined;
    },
    kvHas: (key: string) => kvStore.has(key),
  };
}

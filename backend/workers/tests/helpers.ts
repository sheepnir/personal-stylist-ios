/**
 * Shared in-memory KV for Workers unit tests.
 */

import {
  ageLedger,
  emptyLedgerState,
  reconcileAttempt,
  reserveAttempt,
  summarizeDay,
  type LedgerState,
} from '../src/ledgerCore.js';
import type { SpendConfig } from '../src/types.js';

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
        return reserveAttempt(state, attemptId, upperBoundUSD, day, config, task);
      },
      reconcile: async (attemptId: string, actualUSD: number, task?: string) => {
        const state = stateFor(deviceId);
        ageLedger(state, new Date());
        return reconcileAttempt(state, attemptId, actualUSD, task);
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

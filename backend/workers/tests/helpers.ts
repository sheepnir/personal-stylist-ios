/**
 * Shared in-memory KV for Workers unit tests.
 */

import { NO_COST_SOURCE } from '../src/costSource.js';
import {
  ageLedger,
  emptyLedgerState,
  markAttemptUnknown,
  reconcileAttempt,
  reserveAttempt,
  summarizeDay,
  countUnresolvedAttemptsAcrossDays,
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

export type SpendLedgerTestHarness = DurableObjectNamespace & {
  markUnknownCalls: Array<{ deviceId: string; attemptId: string; generationId?: string }>;
};

/** In-memory per-device spend ledger stub (same API as DeviceSpendLedger). */
export function spendLedger(): SpendLedgerTestHarness {
  const byDevice = new Map<string, LedgerState>();
  const markUnknownCalls: SpendLedgerTestHarness['markUnknownCalls'] = [];

  const stateFor = (deviceId: string): LedgerState => {
    let state = byDevice.get(deviceId);
    if (!state) {
      state = emptyLedgerState();
      byDevice.set(deviceId, state);
    }
    return state;
  };

  return {
    getByName: (deviceId: string) => ({
      reserve: async (
        attemptId: string,
        upperBoundUSD: number,
        day: string,
        config: SpendConfig
      ) => {
        const state = stateFor(deviceId);
        ageLedger(state, new Date(), NO_COST_SOURCE);
        const result = reserveAttempt(state, attemptId, upperBoundUSD, day, config);
        return result;
      },
      reconcile: async (attemptId: string, actualUSD: number) => {
        const state = stateFor(deviceId);
        ageLedger(state, new Date(), NO_COST_SOURCE);
        return reconcileAttempt(state, attemptId, actualUSD);
      },
      summary: async (day: string, config: SpendConfig) => {
        const state = stateFor(deviceId);
        ageLedger(state, new Date(), NO_COST_SOURCE);
        return summarizeDay(state, day, config);
      },
      markUnknown: async (attemptId: string, generationId?: string) => {
        markUnknownCalls.push({ deviceId, attemptId, generationId });
        const state = stateFor(deviceId);
        ageLedger(state, new Date(), NO_COST_SOURCE);
        const result = markAttemptUnknown(state, attemptId, generationId);
        return result;
      },
      unresolvedAttempts: async () => {
        const state = stateFor(deviceId);
        ageLedger(state, new Date(), NO_COST_SOURCE);
        return countUnresolvedAttemptsAcrossDays(state);
      },
    }),
    markUnknownCalls,
  } as unknown as SpendLedgerTestHarness;
}

import { DurableObject } from 'cloudflare:workers';
import type { Env, SpendConfig } from './types.js';
import {
  ageLedger,
  configToMicro,
  failClosedDaySummary,
  isLegacyStorageBlocked,
  reconcileAttempt,
  removeEmptyDayBucket,
  reserveAttempt,
  summarizeDay,
  type ReconcileResult,
  type ReserveResult,
  type DaySummary,
} from './ledgerCore.js';
import {
  dayKeysInStorage,
  loadLedgerFromStorage,
  persistLedgerToStorage,
} from './ledgerBucketStorage.js';
import {
  toRpcDaySummary,
  toRpcReconcileResult,
  toRpcReserveResult,
} from './rpcPlain.js';

/** Per-device spend ledger (keyed by device locator id, not token hash). */
export class DeviceSpendLedger extends DurableObject<Env> {
  private touch(now = new Date()): {
    dayKeysBefore: Set<string>;
    state: ReturnType<typeof loadLedgerFromStorage>;
    pruned: boolean;
  } {
    const dayKeysBefore = dayKeysInStorage(this.ctx.storage.kv);
    const state = loadLedgerFromStorage(this.ctx.storage.kv);
    const pruned = ageLedger(state, now);
    return { dayKeysBefore, state, pruned };
  }

  private persist(
    state: ReturnType<typeof loadLedgerFromStorage>,
    dayKeysBefore: Set<string>
  ): boolean {
    return persistLedgerToStorage(this.ctx.storage.kv, state, dayKeysBefore).ok;
  }

  reserve(
    attemptId: string,
    upperBoundUSD: number,
    day: string,
    config: SpendConfig,
    task = 'unknown'
  ): ReserveResult {
    return this.ctx.storage.transactionSync(() => {
      const { dayKeysBefore, state, pruned } = this.touch();
      if (isLegacyStorageBlocked(state)) {
        if (pruned && !this.persist(state, dayKeysBefore)) {
          return toRpcReserveResult({ ok: false, reason: 'storage_error' });
        }
        return toRpcReserveResult({ ok: false, reason: 'storage_error' });
      }
      if (!configToMicro(config).ok) {
        if (pruned && !this.persist(state, dayKeysBefore)) {
          return toRpcReserveResult({ ok: false, reason: 'storage_error' });
        }
        return toRpcReserveResult({ ok: false, reason: 'config_error' });
      }
      const result = reserveAttempt(state, attemptId, upperBoundUSD, day, config, task);
      if (!result.ok) {
        removeEmptyDayBucket(state, day);
      }
      if (result.ok || pruned) {
        if (!this.persist(state, dayKeysBefore)) {
          return toRpcReserveResult({ ok: false, reason: 'storage_error' });
        }
      }
      return toRpcReserveResult(result);
    });
  }

  reconcile(day: string, attemptId: string, actualUSD: number, task?: string): ReconcileResult {
    return this.ctx.storage.transactionSync(() => {
      const { dayKeysBefore, state, pruned } = this.touch();
      if (isLegacyStorageBlocked(state)) {
        if (pruned && !this.persist(state, dayKeysBefore)) {
          return toRpcReconcileResult({ ok: false, reason: 'storage_error' });
        }
        return toRpcReconcileResult({ ok: false, reason: 'storage_error' });
      }
      const result = reconcileAttempt(state, day, attemptId, actualUSD, task);
      if (result.ok || pruned || result.reason === 'actual_over_ceiling') {
        if (!this.persist(state, dayKeysBefore)) {
          return toRpcReconcileResult({ ok: false, reason: 'storage_error' });
        }
      }
      return toRpcReconcileResult(result);
    });
  }

  /** Reserved for #13-b — not implemented in #13-a. */
  markUnknown(_day: string, _attemptId: string, _generationId?: string): { ok: boolean } {
    return { ok: false };
  }

  summary(day: string, config: SpendConfig): DaySummary {
    return this.ctx.storage.transactionSync(() => {
      const { dayKeysBefore, state, pruned } = this.touch();
      if (isLegacyStorageBlocked(state)) {
        if (pruned && !this.persist(state, dayKeysBefore)) {
          return toRpcDaySummary(failClosedDaySummary(day));
        }
        return toRpcDaySummary(summarizeDay(state, day, config));
      }
      if (!configToMicro(config).ok) {
        if (pruned && !this.persist(state, dayKeysBefore)) {
          return toRpcDaySummary(failClosedDaySummary(day));
        }
        return toRpcDaySummary(failClosedDaySummary(day));
      }
      const summary = summarizeDay(state, day, config);
      if (pruned && !this.persist(state, dayKeysBefore)) {
        return toRpcDaySummary(failClosedDaySummary(day));
      }
      return toRpcDaySummary(summary);
    });
  }
}

export function shouldPersistInMemoryLedger(
  resultOk: boolean,
  pruned: boolean,
  keysBefore: string,
  keysAfter: string
): boolean {
  return resultOk || pruned || keysBefore !== keysAfter;
}

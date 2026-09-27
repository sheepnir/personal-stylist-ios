import { DurableObject } from 'cloudflare:workers';
import { boundedJSON, object } from './jev.js';
import type { Env, SpendConfig } from './types.js';
import {
  ageLedger,
  configToMicro,
  failClosedDaySummary,
  isLegacyStorageBlocked,
  markAttemptUnknown,
  reconcileAttempt,
  removeEmptyDayBucket,
  reserveAttempt,
  summarizeDay,
  type MarkUnknownResult,
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
  providerEnabled(): boolean { return this.ctx.storage.kv.get('provider-enabled') === true; }

  setProviderEnabled(enabled: boolean): void {
    if (typeof enabled !== 'boolean') throw new Error('INVALID_SWITCH');
    this.ctx.storage.kv.put('provider-enabled', enabled);
  }

  /** Daily cap and cumulative evaluation reservation bound share one transaction.
   * The cumulative bound never refunds or resets, deliberately over-counting.
   */
  reserveGlobal(attemptId: string, upperBoundUSD: number, day: string, config: SpendConfig,
    totalCapUSD: number, task: string): ReserveResult {
    return this.ctx.storage.transactionSync(() => {
      if (!this.providerEnabled()) return { ok: false, reason: 'config_error' };
      const cap = configToMicro({ dailyCapUSD: totalCapUSD, softThresholdUSD: totalCapUSD });
      const used = this.ctx.storage.kv.get<number>('evaluation-reserved-micro') ?? 0;
      const amount = Math.ceil(upperBoundUSD * 1e6);
      if (!cap.ok || !Number.isSafeInteger(used) || used < 0 || !Number.isSafeInteger(amount) || amount <= 0) return { ok: false, reason: 'hard_cap' };
      const { state, dayKeysBefore } = this.touch();
      if (isLegacyStorageBlocked(state)) return { ok: false, reason: 'storage_error' };
      const prior = Object.values(state.days).some(d => Object.hasOwn(d.attempts, attemptId));
      if (!prior && used + amount > cap.capMicro) return { ok: false, reason: 'hard_cap' };
      const result = reserveAttempt(state, attemptId, upperBoundUSD, day, config, task);
      if (!result.ok) return toRpcReserveResult(result);
      if (!this.persist(state, dayKeysBefore)) throw new Error('LEDGER_STORAGE');
      if (!prior) this.ctx.storage.kv.put('evaluation-reserved-micro', used + amount);
      return toRpcReserveResult(result);
    });
  }

  /** Network happens outside the storage transaction. Applying known costs is atomic. */
  async alarm(): Promise<void> {
    const due = this.ctx.storage.transactionSync(() => {
      const { state, dayKeysBefore } = this.touch();
      const requests: { day: string; attempt: string; generation: string }[] = [];
      ageLedger(state, new Date(), { lookup: (generation, attempt) => {
        for (const [day, bucket] of Object.entries(state.days)) {
          if (Object.hasOwn(bucket.attempts, attempt)) requests.push({ day, attempt, generation });
        }
        return { outcome: 'unknown' };
      } }, 20);
      if (!this.persist(state, dayKeysBefore)) throw new Error('LEDGER_STORAGE');
      return requests;
    });
    for (const item of due) {
      if (!this.env.OPENROUTER_API_KEY) break;
      try {
        const response = await fetch('https://openrouter.ai/api/v1/generation?id=' + encodeURIComponent(item.generation), {
          headers: { Authorization: `Bearer ${this.env.OPENROUTER_API_KEY}` }, signal: AbortSignal.timeout(3000),
        });
        if (!response.ok) { await response.body?.cancel(); continue; }
        const data = object(object(await boundedJSON(response)).data);
        if (typeof data.total_cost === 'number' && Number.isFinite(data.total_cost) && data.total_cost >= 0) {
          this.reconcile(item.day, item.attempt, data.total_cost);
        }
      } catch { /* Unknown remains reserved; no upstream error body enters logs. */ }
    }
    const pending = this.ctx.storage.transactionSync(() => {
      const { state, dayKeysBefore } = this.touch();
      if (!this.persist(state, dayKeysBefore)) throw new Error('LEDGER_STORAGE');
      return Object.values(state.days).some(d => Object.values(d.attempts).some(a => a.state !== 'reconciled'));
    });
    if (pending) await this.ctx.storage.setAlarm(Date.now() + 60_000);
  }

  private touch(now = new Date()): {
    dayKeysBefore: Set<string>;
    state: ReturnType<typeof loadLedgerFromStorage>;
    pruned: boolean;
  } {
    const dayKeysBefore = dayKeysInStorage(this.ctx.storage.kv);
    const state = loadLedgerFromStorage(this.ctx.storage.kv);
    const before = JSON.stringify(state);
    const keysPruned = ageLedger(state, now);
    const pruned = keysPruned || JSON.stringify(state) !== before;
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

  /** Day is accepted for RPC symmetry; lookup is by attemptId across buckets (#13-b). */
  markUnknown(_day: string, attemptId: string, generationId?: string): MarkUnknownResult {
    return this.ctx.storage.transactionSync(() => {
      const { dayKeysBefore, state, pruned } = this.touch();
      if (isLegacyStorageBlocked(state)) {
        return { ok: false, reason: 'invalid' };
      }
      if (generationId !== undefined && !/^[a-zA-Z0-9_-]{1,128}$/.test(generationId)) return { ok: false, reason: 'invalid' };
      const result = markAttemptUnknown(state, attemptId, generationId);
      if (result.ok || pruned) {
        if (!this.persist(state, dayKeysBefore)) {
          return { ok: false, reason: 'invalid' };
        }
      }
      if (result.ok) this.ctx.waitUntil(this.ctx.storage.setAlarm(Date.now() + 1000));
      return result;
    });
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

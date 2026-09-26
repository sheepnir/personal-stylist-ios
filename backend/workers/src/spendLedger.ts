import { DurableObject } from 'cloudflare:workers';
import type { Env, SpendConfig } from './types.js';
import {
  ageLedger,
  emptyLedgerState,
  reconcileAttempt,
  removeEmptyDayBucket,
  reserveAttempt,
  summarizeDay,
  type LedgerState,
  type ReconcileResult,
  type ReserveResult,
  type DaySummary,
} from './ledgerCore.js';

const STATE_KEY = 'ledger';

function dayKeySnapshot(state: LedgerState): string {
  return Object.keys(state.days).sort().join('\0');
}

/** Per-device spend ledger (keyed by device locator id, not token hash). */
export class DeviceSpendLedger extends DurableObject<Env> {
  private loadState(): LedgerState {
    return this.ctx.storage.kv.get<LedgerState>(STATE_KEY) ?? emptyLedgerState();
  }

  private saveState(state: LedgerState): void {
    this.ctx.storage.kv.put(STATE_KEY, state);
  }

  private touch(now = new Date()): { state: LedgerState; pruned: boolean } {
    const state = this.loadState();
    const pruned = ageLedger(state, now);
    return { state, pruned };
  }

  reserve(
    attemptId: string,
    upperBoundUSD: number,
    day: string,
    config: SpendConfig,
    task = 'unknown'
  ): ReserveResult {
    return this.ctx.storage.transactionSync(() => {
      const { state, pruned } = this.touch();
      const result = reserveAttempt(state, attemptId, upperBoundUSD, day, config, task);
      if (!result.ok) {
        removeEmptyDayBucket(state, day);
      }
      if (result.ok || pruned) {
        this.saveState(state);
      }
      return result;
    });
  }

  reconcile(attemptId: string, actualUSD: number, task?: string): ReconcileResult {
    return this.ctx.storage.transactionSync(() => {
      const { state, pruned } = this.touch();
      const result = reconcileAttempt(state, attemptId, actualUSD, task);
      if (result.ok || pruned) {
        this.saveState(state);
      }
      return result;
    });
  }

  /** Reserved for #13-b — not implemented in #13-a. */
  markUnknown(_attemptId: string, _generationId?: string): { ok: boolean } {
    return { ok: false };
  }

  summary(day: string, config: SpendConfig): DaySummary {
    return this.ctx.storage.transactionSync(() => {
      const { state, pruned } = this.touch();
      const summary = summarizeDay(state, day, config);
      if (pruned) {
        this.saveState(state);
      }
      return summary;
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

import { DurableObject } from 'cloudflare:workers';
import type { Env, SpendConfig } from './types.js';
import {
  ageLedger,
  emptyLedgerState,
  reconcileAttempt,
  reserveAttempt,
  summarizeDay,
  type LedgerState,
  type ReconcileResult,
  type ReserveResult,
  type DaySummary,
} from './ledgerCore.js';

const STATE_KEY = 'ledger';

/** Per-device spend ledger (keyed by device locator id, not token hash). */
export class DeviceSpendLedger extends DurableObject<Env> {
  private loadState(): LedgerState {
    return this.ctx.storage.kv.get<LedgerState>(STATE_KEY) ?? emptyLedgerState();
  }

  private saveState(state: LedgerState): void {
    this.ctx.storage.kv.put(STATE_KEY, state);
  }

  /** Lazy aging hook (#13-b extends this); always prunes stale day buckets. */
  private touch(now = new Date()): LedgerState {
    const state = this.loadState();
    ageLedger(state, now);
    return state;
  }

  reserve(
    attemptId: string,
    upperBoundUSD: number,
    day: string,
    config: SpendConfig
  ): ReserveResult {
    return this.ctx.storage.transactionSync(() => {
      const state = this.touch();
      const result = reserveAttempt(state, attemptId, upperBoundUSD, day, config);
      if (result.ok) this.saveState(state);
      return result;
    });
  }

  reconcile(attemptId: string, actualUSD: number): ReconcileResult {
    return this.ctx.storage.transactionSync(() => {
      const state = this.touch();
      const result = reconcileAttempt(state, attemptId, actualUSD);
      if (result.ok) this.saveState(state);
      return result;
    });
  }

  /** Reserved for #13-b — not implemented in #13-a. */
  markUnknown(_attemptId: string, _generationId?: string): { ok: boolean } {
    return { ok: false };
  }

  summary(day: string, config: SpendConfig): DaySummary {
    return this.ctx.storage.transactionSync(() => {
      const state = this.touch();
      this.saveState(state);
      return summarizeDay(state, day, config);
    });
  }
}

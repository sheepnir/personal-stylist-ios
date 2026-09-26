import { DurableObject } from 'cloudflare:workers';
import { NO_COST_SOURCE } from './costSource.js';
import type { Env, SpendConfig } from './types.js';
import {
  ageLedger,
  emptyLedgerState,
  markAttemptUnknown,
  reconcileAttempt,
  reserveAttempt,
  summarizeDay,
  countUnresolvedAttemptsAcrossDays,
  type LedgerState,
  type MarkUnknownResult,
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
    ageLedger(state, now, NO_COST_SOURCE);
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

  markUnknown(attemptId: string, generationId?: string): MarkUnknownResult {
    return this.ctx.storage.transactionSync(() => {
      const state = this.touch();
      const result = markAttemptUnknown(state, attemptId, generationId);
      if (result.ok) this.saveState(state);
      return result;
    });
  }

  summary(day: string, config: SpendConfig): DaySummary {
    return this.ctx.storage.transactionSync(() => {
      const state = this.touch();
      this.saveState(state);
      return summarizeDay(state, day, config);
    });
  }

  /** Count unknown attempts on every retained ledger day (not yet aged to spent). */
  unresolvedAttempts(): number {
    return this.ctx.storage.transactionSync(() => {
      const state = this.touch();
      this.saveState(state);
      return countUnresolvedAttemptsAcrossDays(state);
    });
  }
}

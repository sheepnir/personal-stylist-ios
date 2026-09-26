/**
 * Pure spend-ledger logic (reserve / reconcile / summary / prune).
 * Used inside DeviceSpendLedger transactions and unit-tested without workerd.
 */

import type { SpendConfig } from './types.js';

export type AttemptState = 'reserved' | 'reconciled' | 'unknown';

export interface AttemptEntry {
  attemptId: string;
  upperBoundUSD: number;
  actualUSD?: number;
  state: AttemptState;
  createdAt: string;
  reconciledAt?: string;
  generationId?: string;
}

export interface DayRecord {
  date: string;
  spentUSD: number;
  reservedUSD: number;
  attempts: Record<string, AttemptEntry>;
  /** Aggregated reconciled spend by task label (content-free). */
  tasks: Record<string, number>;
}

export interface LedgerState {
  days: Record<string, DayRecord>;
}

export const LEDGER_RETENTION_DAYS = 31;

export interface ReserveResult {
  ok: boolean;
  reason?: 'hard_cap' | 'invalid';
}

export interface ReconcileResult {
  ok: boolean;
  reason?: 'not_found' | 'invalid';
}

export interface DaySummary {
  date: string;
  spentUSD: number;
  reservedUSD: number;
  softThresholdReached: boolean;
  hardCapReached: boolean;
  byTask: Record<string, number>;
}

export function emptyLedgerState(): LedgerState {
  return { days: {} };
}

function emptyDay(date: string): DayRecord {
  return {
    date,
    spentUSD: 0,
    reservedUSD: 0,
    attempts: {},
    tasks: {},
  };
}

function getDay(state: LedgerState, date: string): DayRecord {
  return state.days[date] ?? emptyDay(date);
}

/** Drop day buckets older than {@link LEDGER_RETENTION_DAYS} UTC calendar days. */
export function pruneOldDays(state: LedgerState, now: Date): void {
  const cutoff = utcDateString(addUtcDays(now, -LEDGER_RETENTION_DAYS));
  for (const key of Object.keys(state.days)) {
    if (key < cutoff) {
      delete state.days[key];
    }
  }
}

export function reserveAttempt(
  state: LedgerState,
  attemptId: string,
  upperBoundUSD: number,
  day: string,
  config: SpendConfig
): ReserveResult {
  if (!attemptId || !Number.isFinite(upperBoundUSD) || upperBoundUSD < 0) {
    return { ok: false, reason: 'invalid' };
  }

  const dayRecord = getDay(state, day);
  const existing = dayRecord.attempts[attemptId];
  if (existing) {
    if (existing.upperBoundUSD === upperBoundUSD) {
      state.days[day] = dayRecord;
      return { ok: true };
    }
    return { ok: false, reason: 'invalid' };
  }

  const totalCommitted = dayRecord.spentUSD + dayRecord.reservedUSD;
  if (totalCommitted + upperBoundUSD > config.dailyCapUSD) {
    return { ok: false, reason: 'hard_cap' };
  }

  dayRecord.attempts[attemptId] = {
    attemptId,
    upperBoundUSD,
    state: 'reserved',
    createdAt: new Date().toISOString(),
  };
  dayRecord.reservedUSD += upperBoundUSD;
  state.days[day] = dayRecord;
  return { ok: true };
}

export function reconcileAttempt(
  state: LedgerState,
  attemptId: string,
  actualUSD: number
): ReconcileResult {
  if (!attemptId || !Number.isFinite(actualUSD) || actualUSD < 0) {
    return { ok: false, reason: 'invalid' };
  }

  for (const day of Object.values(state.days)) {
    const entry = day.attempts[attemptId];
    if (!entry) continue;

    if (entry.state === 'reconciled' && entry.actualUSD === actualUSD) {
      return { ok: true };
    }
    if (entry.state !== 'reserved') {
      return { ok: false, reason: 'invalid' };
    }

    day.reservedUSD -= entry.upperBoundUSD;
    day.spentUSD += actualUSD;
    entry.state = 'reconciled';
    entry.actualUSD = actualUSD;
    entry.reconciledAt = new Date().toISOString();
    return { ok: true };
  }

  return { ok: false, reason: 'not_found' };
}

export function summarizeDay(
  state: LedgerState,
  day: string,
  config: SpendConfig
): DaySummary {
  const record = getDay(state, day);
  const totalCommitted = record.spentUSD + record.reservedUSD;
  return {
    date: day,
    spentUSD: record.spentUSD,
    reservedUSD: record.reservedUSD,
    softThresholdReached: totalCommitted >= config.softThresholdUSD,
    hardCapReached: totalCommitted >= config.dailyCapUSD,
    byTask: { ...record.tasks },
  };
}

/** Placeholder for #13-b; prunes only today via {@link pruneOldDays}. */
export function ageLedger(state: LedgerState, now: Date): void {
  pruneOldDays(state, now);
}

function utcDateString(d: Date): string {
  return d.toISOString().split('T')[0];
}

function addUtcDays(d: Date, delta: number): Date {
  const copy = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  copy.setUTCDate(copy.getUTCDate() + delta);
  return copy;
}

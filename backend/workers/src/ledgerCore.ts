/**
 * Pure spend-ledger logic (reserve / reconcile / summary / prune / unknown aging).
 * Used inside DeviceSpendLedger transactions and unit-tested without workerd.
 */

import type { CostSource } from './costSource.js';
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
  /** Lazy CostSource lookups for unknown outcomes (#13-b). */
  costLookupCount?: number;
  lastCostLookupAt?: string;
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

/** ADR-0001 §12 / D-34: unknown reservations count as spent after 24 h. */
export const UNKNOWN_OUTCOME_AGING_MS = 24 * 60 * 60 * 1000;

/**
 * Increasing intervals between lazy CostSource lookups (first lookup on first ledger access).
 */
export const COST_LOOKUP_BACKOFF_MS = [
  0,
  60_000,
  5 * 60_000,
  15 * 60_000,
  60 * 60_000,
  4 * 60 * 60_000,
];

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
    if (entry.state !== 'reserved' && entry.state !== 'unknown') {
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

export interface MarkUnknownResult {
  ok: boolean;
  reason?: 'not_found' | 'invalid';
}

/** Move a reserved attempt to unknown; funds stay reserved until reconcile or aging. */
export function markAttemptUnknown(
  state: LedgerState,
  attemptId: string,
  generationId?: string
): MarkUnknownResult {
  if (!attemptId) {
    return { ok: false, reason: 'invalid' };
  }

  for (const day of Object.values(state.days)) {
    const entry = day.attempts[attemptId];
    if (!entry) continue;

    if (entry.state === 'unknown') {
      if (generationId !== undefined && entry.generationId !== undefined && entry.generationId !== generationId) {
        return { ok: false, reason: 'invalid' };
      }
      if (generationId !== undefined) entry.generationId = generationId;
      return { ok: true };
    }
    if (entry.state !== 'reserved') {
      return { ok: false, reason: 'invalid' };
    }

    entry.state = 'unknown';
    if (generationId !== undefined) entry.generationId = generationId;
    return { ok: true };
  }

  return { ok: false, reason: 'not_found' };
}

function finalizeAgedUnknown(day: DayRecord, entry: AttemptEntry, now: Date): void {
  day.reservedUSD -= entry.upperBoundUSD;
  day.spentUSD += entry.upperBoundUSD;
  entry.state = 'reconciled';
  entry.actualUSD = entry.upperBoundUSD;
  entry.reconciledAt = now.toISOString();
}

function shouldAttemptCostLookup(entry: AttemptEntry, now: Date): boolean {
  if (!entry.generationId) return false;

  const createdMs = Date.parse(entry.createdAt);
  const ageMs = now.getTime() - createdMs;
  if (ageMs >= UNKNOWN_OUTCOME_AGING_MS) return false;

  const count = entry.costLookupCount ?? 0;
  const backoff =
    COST_LOOKUP_BACKOFF_MS[Math.min(count, COST_LOOKUP_BACKOFF_MS.length - 1)];
  const anchorMs =
    count === 0 ? createdMs : Date.parse(entry.lastCostLookupAt ?? entry.createdAt);
  return now.getTime() >= anchorMs + backoff;
}

function processUnknownAttempts(state: LedgerState, now: Date, costSource: CostSource): void {
  for (const day of Object.values(state.days)) {
    for (const entry of Object.values(day.attempts)) {
      if (entry.state !== 'unknown') continue;

      const ageMs = now.getTime() - Date.parse(entry.createdAt);
      if (ageMs >= UNKNOWN_OUTCOME_AGING_MS) {
        finalizeAgedUnknown(day, entry, now);
        continue;
      }

      if (!shouldAttemptCostLookup(entry, now)) continue;

      entry.lastCostLookupAt = now.toISOString();
      entry.costLookupCount = (entry.costLookupCount ?? 0) + 1;

      const generationId = entry.generationId;
      if (!generationId) continue;

      const lookup = costSource.lookup(generationId, entry.attemptId);
      if (lookup.outcome === 'known' && lookup.costUSD !== undefined) {
        reconcileAttempt(state, entry.attemptId, lookup.costUSD);
      }
      // `unknown` and `error` leave the reservation in place (failed reconciliation never releases).
    }
  }
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

/**
 * Prune stale days, age unknown outcomes at 24 h, and lazily reconcile via {@link CostSource}.
 */
export function ageLedger(state: LedgerState, now: Date, costSource: CostSource): void {
  processUnknownAttempts(state, now, costSource);
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

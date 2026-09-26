/**
 * Pure spend-ledger logic (reserve / reconcile / summary / prune).
 * All monetary amounts inside the ledger are integer micro-USD (1 USD = 1_000_000 micro).
 */

import type { SpendConfig } from './types.js';

export const MICRO_USD = 1_000_000;

export type AttemptState = 'reserved' | 'reconciled' | 'unknown';

export interface AttemptEntry {
  attemptId: string;
  upperBoundMicro: number;
  actualMicro?: number;
  task: string;
  state: AttemptState;
  createdAt: string;
  reconciledAt?: string;
  generationId?: string;
}

export interface DayRecord {
  date: string;
  spentMicro: number;
  reservedMicro: number;
  /** Count of reconciles where actual cost exceeded the reserved upper bound. */
  overReservationCount: number;
  attempts: Record<string, AttemptEntry>;
  /** Reconciled spend by task label (micro-USD). */
  tasks: Record<string, number>;
}

export interface LedgerState {
  days: Record<string, DayRecord>;
}

/** UTC calendar days retained (inclusive); buckets strictly older than this are pruned. */
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
  overReservationCount: number;
  byTask: Record<string, number>;
}

export function usdToMicro(usd: number): number {
  return Math.round(usd * MICRO_USD);
}

export function microToUsd(micro: number): number {
  return micro / MICRO_USD;
}

export function configToMicro(config: SpendConfig): { capMicro: number; softMicro: number } {
  return {
    capMicro: usdToMicro(config.dailyCapUSD),
    softMicro: usdToMicro(config.softThresholdUSD),
  };
}

export function emptyLedgerState(): LedgerState {
  return { days: {} };
}

function emptyDay(date: string): DayRecord {
  return {
    date,
    spentMicro: 0,
    reservedMicro: 0,
    overReservationCount: 0,
    attempts: {},
    tasks: {},
  };
}

function getDay(state: LedgerState, date: string): DayRecord {
  const existing = state.days[date];
  if (existing) return existing;
  const day = emptyDay(date);
  state.days[date] = day;
  return day;
}

function utcDayString(d: Date): string {
  return d.toISOString().split('T')[0];
}

function utcDayAgeDays(day: string, now: Date): number {
  const dayMs = Date.parse(`${day}T00:00:00.000Z`);
  const nowMs = Date.parse(`${utcDayString(now)}T00:00:00.000Z`);
  return Math.floor((nowMs - dayMs) / 86_400_000);
}

/**
 * Prune day buckets strictly older than {@link LEDGER_RETENTION_DAYS} UTC calendar days.
 * A bucket on the boundary (exactly 31 days old) is kept.
 */
export function pruneOldDays(state: LedgerState, now: Date): void {
  for (const key of Object.keys(state.days)) {
    if (utcDayAgeDays(key, now) > LEDGER_RETENTION_DAYS) {
      delete state.days[key];
    }
  }
}

function findAttempt(
  state: LedgerState,
  attemptId: string
): { day: DayRecord; entry: AttemptEntry } | null {
  for (const day of Object.values(state.days)) {
    const entry = day.attempts[attemptId];
    if (entry) return { day, entry };
  }
  return null;
}

export function reserveAttempt(
  state: LedgerState,
  attemptId: string,
  upperBoundUSD: number,
  day: string,
  config: SpendConfig,
  task = 'unknown'
): ReserveResult {
  if (!attemptId || !Number.isFinite(upperBoundUSD) || upperBoundUSD < 0) {
    return { ok: false, reason: 'invalid' };
  }

  const upperBoundMicro = usdToMicro(upperBoundUSD);
  const { capMicro, softMicro: _softMicro } = configToMicro(config);

  const existingGlobal = findAttempt(state, attemptId);
  if (existingGlobal) {
    if (existingGlobal.entry.upperBoundMicro === upperBoundMicro) {
      return { ok: true };
    }
    return { ok: false, reason: 'invalid' };
  }

  const dayRecord = getDay(state, day);

  if (dayRecord.spentMicro >= capMicro) {
    return { ok: false, reason: 'hard_cap' };
  }

  const totalCommitted = dayRecord.spentMicro + dayRecord.reservedMicro;
  if (totalCommitted + upperBoundMicro > capMicro) {
    return { ok: false, reason: 'hard_cap' };
  }

  dayRecord.attempts[attemptId] = {
    attemptId,
    upperBoundMicro,
    task,
    state: 'reserved',
    createdAt: new Date().toISOString(),
  };
  dayRecord.reservedMicro += upperBoundMicro;
  return { ok: true };
}

export function reconcileAttempt(
  state: LedgerState,
  attemptId: string,
  actualUSD: number,
  task?: string
): ReconcileResult {
  if (!attemptId || !Number.isFinite(actualUSD) || actualUSD < 0) {
    return { ok: false, reason: 'invalid' };
  }

  const located = findAttempt(state, attemptId);
  if (!located) {
    return { ok: false, reason: 'not_found' };
  }

  const { day, entry } = located;
  const actualMicro = usdToMicro(actualUSD);

  if (entry.state === 'reconciled' && entry.actualMicro === actualMicro) {
    return { ok: true };
  }
  if (entry.state !== 'reserved') {
    return { ok: false, reason: 'invalid' };
  }

  day.reservedMicro -= entry.upperBoundMicro;
  day.spentMicro += actualMicro;
  if (actualMicro > entry.upperBoundMicro) {
    day.overReservationCount += 1;
  }

  const taskKey = task ?? entry.task;
  day.tasks[taskKey] = (day.tasks[taskKey] ?? 0) + actualMicro;

  entry.state = 'reconciled';
  entry.actualMicro = actualMicro;
  entry.reconciledAt = new Date().toISOString();
  return { ok: true };
}

export function summarizeDay(
  state: LedgerState,
  day: string,
  config: SpendConfig
): DaySummary {
  const record = getDay(state, day);
  const { capMicro, softMicro } = configToMicro(config);
  const totalCommitted = record.spentMicro + record.reservedMicro;
  const byTask: Record<string, number> = {};
  for (const [task, micro] of Object.entries(record.tasks)) {
    byTask[task] = microToUsd(micro);
  }
  return {
    date: day,
    spentUSD: microToUsd(record.spentMicro),
    reservedUSD: microToUsd(record.reservedMicro),
    softThresholdReached: totalCommitted >= softMicro,
    hardCapReached: record.spentMicro >= capMicro,
    overReservationCount: record.overReservationCount,
    byTask,
  };
}

/** Placeholder for #13-b; prunes stale day buckets on every call. */
export function ageLedger(state: LedgerState, now: Date): void {
  pruneOldDays(state, now);
}

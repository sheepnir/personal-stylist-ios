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

/** UTC calendar days retained (inclusive); fully settled buckets strictly older than this may be pruned. */
export const LEDGER_RETENTION_DAYS = 31;

const DAY_KEY_RE = /^\d{4}-\d{2}-\d{2}$/;

export interface ReserveResult {
  ok: boolean;
  reason?: 'hard_cap' | 'invalid' | 'already_settled';
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

/** Strict UTC calendar day key (YYYY-MM-DD) that matches a real calendar date. */
export function isValidLedgerDayKey(day: string): boolean {
  if (!DAY_KEY_RE.test(day)) return false;
  const ms = Date.parse(`${day}T00:00:00.000Z`);
  if (!Number.isFinite(ms)) return false;
  return utcDayString(new Date(ms)) === day;
}

function isPositiveUsd(amount: number): boolean {
  return Number.isFinite(amount) && amount > 0;
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

function getOrCreateDay(state: LedgerState, date: string): DayRecord {
  const existing = state.days[date];
  if (existing) return existing;
  const day = emptyDay(date);
  state.days[date] = day;
  return day;
}

function readDay(state: LedgerState, date: string): DayRecord {
  return state.days[date] ?? emptyDay(date);
}

function utcDayString(d: Date): string {
  return d.toISOString().split('T')[0];
}

function utcDayAgeDays(day: string, now: Date): number {
  const dayMs = Date.parse(`${day}T00:00:00.000Z`);
  const nowMs = Date.parse(`${utcDayString(now)}T00:00:00.000Z`);
  return Math.floor((nowMs - dayMs) / 86_400_000);
}

function dayIsFullySettled(day: DayRecord): boolean {
  for (const entry of Object.values(day.attempts)) {
    if (entry.state === 'reserved' || entry.state === 'unknown') {
      return false;
    }
  }
  return true;
}

/**
 * Prune day buckets strictly older than {@link LEDGER_RETENTION_DAYS} UTC calendar days
 * when every attempt on that day is settled (reconciled). Open reservations are never dropped.
 * Malformed day keys are always removed.
 */
export function pruneOldDays(state: LedgerState, now: Date): void {
  for (const key of Object.keys(state.days)) {
    if (!isValidLedgerDayKey(key)) {
      delete state.days[key];
      continue;
    }
    if (utcDayAgeDays(key, now) > LEDGER_RETENTION_DAYS && dayIsFullySettled(state.days[key])) {
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
  if (!attemptId || !isPositiveUsd(upperBoundUSD)) {
    return { ok: false, reason: 'invalid' };
  }
  if (!isValidLedgerDayKey(day)) {
    return { ok: false, reason: 'invalid' };
  }

  const upperBoundMicro = usdToMicro(upperBoundUSD);
  const { capMicro } = configToMicro(config);

  const existingGlobal = findAttempt(state, attemptId);
  if (existingGlobal) {
    if (existingGlobal.entry.state === 'reconciled' || existingGlobal.entry.state === 'unknown') {
      return { ok: false, reason: 'already_settled' };
    }
    if (existingGlobal.entry.upperBoundMicro === upperBoundMicro) {
      return { ok: true };
    }
    return { ok: false, reason: 'invalid' };
  }

  const dayRecord = getOrCreateDay(state, day);

  if (dayRecord.spentMicro >= capMicro) {
    return { ok: false, reason: 'hard_cap' };
  }

  const totalCommitted = dayRecord.spentMicro + dayRecord.reservedMicro;
  if (totalCommitted >= capMicro || totalCommitted + upperBoundMicro > capMicro) {
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
  if (!attemptId || !isPositiveUsd(actualUSD)) {
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
  if (!isValidLedgerDayKey(day)) {
    return {
      date: day,
      spentUSD: 0,
      reservedUSD: 0,
      softThresholdReached: false,
      hardCapReached: false,
      overReservationCount: 0,
      byTask: {},
    };
  }

  const record = readDay(state, day);
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

/** Placeholder for #13-b; prunes eligible settled buckets and malformed keys on every call. */
export function ageLedger(state: LedgerState, now: Date): void {
  pruneOldDays(state, now);
}

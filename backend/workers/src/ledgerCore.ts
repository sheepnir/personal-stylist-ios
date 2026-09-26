/**
 * Pure spend-ledger logic (reserve / reconcile / summary / prune).
 * All monetary amounts inside the ledger are integer micro-USD (1 USD = 1_000_000 micro).
 */

import type { SpendConfig } from './types.js';

export const MICRO_USD = 1_000_000;

/** Largest deployable daily cap (USD); larger configured values are rejected. */
export const MAX_DEPLOYABLE_CAP_USD = 1_000_000;

/** Largest actual provider cost (USD) accepted on a single reconcile. */
export const MAX_SINGLE_RECONCILE_USD = 10_000;

export const MAX_SINGLE_RECONCILE_MICRO = MAX_SINGLE_RECONCILE_USD * MICRO_USD;

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
  /** True when reconciled actual cost exceeded the reserved upper bound. */
  overReservation?: boolean;
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

/** Retain today plus the 30 preceding UTC calendar days (31 buckets). */
export const LEDGER_DAY_BUCKETS = 31;
export const LEDGER_MAX_DAY_AGE = LEDGER_DAY_BUCKETS - 1;

const DAY_KEY_RE = /^\d{4}-\d{2}-\d{2}$/;

export interface ReserveResult {
  ok: boolean;
  reason?: 'hard_cap' | 'invalid' | 'already_settled' | 'config_error';
}

export interface ReconcileResult {
  ok: boolean;
  reason?: 'not_found' | 'invalid' | 'overflow';
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

export type CostMicroResult = { ok: true; micro: number } | { ok: false };
export type ConfigMicroResult =
  | { ok: true; capMicro: number; softMicro: number }
  | { ok: false; configError: true };

/** Snap float noise before micro-USD rounding (about 1e-3 micro precision). */
export function snapMicroProduct(usd: number): number | null {
  if (typeof usd !== 'number' || !Number.isFinite(usd) || usd <= 0) {
    return null;
  }
  const product = usd * MICRO_USD;
  if (!Number.isFinite(product)) {
    return null;
  }
  const snapped = Math.round(product * 1000) / 1000;
  if (!Number.isFinite(snapped)) {
    return null;
  }
  return snapped;
}

/** Positive finite costs: snap, ceil to micro-USD, minimum 1 micro (including snap-to-zero dust). */
export function costUsdToMicro(usd: number): CostMicroResult {
  if (typeof usd !== 'number' || !Number.isFinite(usd) || usd <= 0) {
    return { ok: false };
  }
  const product = usd * MICRO_USD;
  if (!Number.isFinite(product)) {
    return { ok: false };
  }
  const snapped = Math.round(product * 1000) / 1000;
  if (!Number.isFinite(snapped)) {
    return { ok: false };
  }
  const micro = snapped <= 0 ? 1 : Math.max(1, Math.ceil(snapped));
  if (micro > Number.MAX_SAFE_INTEGER) {
    return { ok: false };
  }
  return { ok: true, micro };
}

/** Caps and thresholds: snap, floor to micro-USD. */
export function capUsdToMicro(usd: number): CostMicroResult {
  const snapped = snapMicroProduct(usd);
  if (snapped === null) {
    return { ok: false };
  }
  const micro = Math.floor(snapped);
  if (micro < 1 || micro > Number.MAX_SAFE_INTEGER) {
    return { ok: false };
  }
  return { ok: true, micro };
}

export function microToUsd(micro: number): number {
  return micro / MICRO_USD;
}

export function configToMicro(config: SpendConfig): ConfigMicroResult {
  if (
    config === undefined ||
    config === null ||
    typeof config.dailyCapUSD !== 'number' ||
    typeof config.softThresholdUSD !== 'number'
  ) {
    return { ok: false, configError: true };
  }
  const cap = capUsdToMicro(config.dailyCapUSD);
  const soft = capUsdToMicro(config.softThresholdUSD);
  if (!cap.ok || !soft.ok) {
    return { ok: false, configError: true };
  }
  return { ok: true, capMicro: cap.micro, softMicro: Math.min(soft.micro, cap.micro) };
}

export function failClosedDaySummary(day: string): DaySummary {
  return {
    date: day,
    spentUSD: 0,
    reservedUSD: 0,
    softThresholdReached: true,
    hardCapReached: true,
    overReservationCount: 0,
    byTask: nullRecord(),
  };
}

/** Strict UTC calendar day key (YYYY-MM-DD) that matches a real calendar date. */
export function isValidLedgerDayKey(day: string): boolean {
  if (!DAY_KEY_RE.test(day)) return false;
  const ms = Date.parse(`${day}T00:00:00.000Z`);
  if (!Number.isFinite(ms)) return false;
  return utcDayString(new Date(ms)) === day;
}

function nullRecord<T extends object>(): T {
  return Object.create(null) as T;
}

export function safeMicroAdd(a: number, b: number): number | null {
  if (!Number.isSafeInteger(a) || !Number.isSafeInteger(b)) {
    return null;
  }
  const sum = a + b;
  return Number.isSafeInteger(sum) ? sum : null;
}

export function safeMicroSub(a: number, b: number): number | null {
  if (!Number.isSafeInteger(a) || !Number.isSafeInteger(b)) {
    return null;
  }
  const diff = a - b;
  return Number.isSafeInteger(diff) ? diff : null;
}

function mapAdd(map: Record<string, number>, key: string, delta: number): boolean {
  const next = safeMicroAdd(Object.hasOwn(map, key) ? map[key] : 0, delta);
  if (next === null) {
    return false;
  }
  map[key] = next;
  return true;
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
    attempts: nullRecord(),
    tasks: nullRecord(),
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

/** Remove a day bucket when it holds no monetary or attempt state. */
export function removeEmptyDayBucket(state: LedgerState, day: string): void {
  const record = state.days[day];
  if (!record) return;
  if (
    record.spentMicro === 0 &&
    record.reservedMicro === 0 &&
    Object.keys(record.attempts).length === 0
  ) {
    delete state.days[day];
  }
}

function utcDayString(d: Date): string {
  return d.toISOString().split('T')[0];
}

function utcDayAgeDays(day: string, now: Date): number {
  const dayMs = Date.parse(`${day}T00:00:00.000Z`);
  const nowMs = Date.parse(`${utcDayString(now)}T00:00:00.000Z`);
  return Math.floor((nowMs - dayMs) / 86_400_000);
}

/** Valid ledger day for mutations: real UTC date, not more than one calendar day ahead of now. */
export function isLedgerDayKeyUsable(day: string, now: Date): boolean {
  if (!isValidLedgerDayKey(day)) {
    return false;
  }
  return utcDayAgeDays(day, now) >= -1;
}

function enforceBucketLimit(state: LedgerState, now: Date): void {
  const keys = Object.keys(state.days);
  if (keys.length <= LEDGER_DAY_BUCKETS) {
    return;
  }
  const sorted = keys.sort((a, b) => {
    const ageA = isValidLedgerDayKey(a) ? utcDayAgeDays(a, now) : Number.MAX_SAFE_INTEGER;
    const ageB = isValidLedgerDayKey(b) ? utcDayAgeDays(b, now) : Number.MAX_SAFE_INTEGER;
    return ageB - ageA;
  });
  for (const key of sorted) {
    if (Object.keys(state.days).length <= LEDGER_DAY_BUCKETS) {
      break;
    }
    const day = state.days[key];
    if (dayHasOpenAttempts(day)) {
      continue;
    }
    delete state.days[key];
  }
}

function dayHasOpenAttempts(day: DayRecord): boolean {
  for (const entry of Object.values(day.attempts)) {
    if (entry.state === 'reserved' || entry.state === 'unknown') {
      return true;
    }
  }
  return false;
}

function dayIsFullySettled(day: DayRecord): boolean {
  return !dayHasOpenAttempts(day);
}

/** Reserved upper bounds on malformed buckets (fail-closed cap headroom). */
function malformedOpenReservedMicro(state: LedgerState): number | null {
  let total = 0;
  for (const [key, day] of Object.entries(state.days)) {
    if (!isValidLedgerDayKey(key) && dayHasOpenAttempts(day)) {
      const next = safeMicroAdd(total, day.reservedMicro);
      if (next === null) {
        return null;
      }
      total = next;
    }
  }
  return total;
}

/**
 * Prune fully settled buckets older than the newest {@link LEDGER_DAY_BUCKETS} UTC days.
 * Buckets with open reservations (including on malformed keys) are never deleted.
 */
export function pruneOldDays(state: LedgerState, now: Date): boolean {
  const keysBefore = Object.keys(state.days).sort().join('\0');
  for (const key of Object.keys(state.days)) {
    const day = state.days[key];
    if (!isValidLedgerDayKey(key)) {
      if (dayHasOpenAttempts(day)) {
        continue;
      }
      delete state.days[key];
      continue;
    }
    const age = utcDayAgeDays(key, now);
    if (age < -1) {
      if (!dayHasOpenAttempts(day)) {
        delete state.days[key];
      }
      continue;
    }
    if (age > LEDGER_MAX_DAY_AGE && dayIsFullySettled(day)) {
      delete state.days[key];
    }
  }
  enforceBucketLimit(state, now);
  const keysAfter = Object.keys(state.days).sort().join('\0');
  return keysBefore !== keysAfter;
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
  task = 'unknown',
  now: Date = new Date()
): ReserveResult {
  const bounds = costUsdToMicro(upperBoundUSD);
  if (!attemptId || !bounds.ok) {
    return { ok: false, reason: 'invalid' };
  }
  if (!isLedgerDayKeyUsable(day, now)) {
    return { ok: false, reason: 'invalid' };
  }

  const configMicro = configToMicro(config);
  if (!configMicro.ok) {
    return { ok: false, reason: 'config_error' };
  }
  const { capMicro } = configMicro;
  const upperBoundMicro = bounds.micro;

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

  const dayRecord = readDay(state, day);
  const conservativeReserved = malformedOpenReservedMicro(state);
  if (conservativeReserved === null) {
    return { ok: false, reason: 'invalid' };
  }

  if (dayRecord.spentMicro >= capMicro) {
    return { ok: false, reason: 'hard_cap' };
  }

  const spentPlusReserved = safeMicroAdd(dayRecord.spentMicro, dayRecord.reservedMicro);
  if (spentPlusReserved === null) {
    return { ok: false, reason: 'invalid' };
  }
  const totalCommitted = safeMicroAdd(spentPlusReserved, conservativeReserved);
  if (totalCommitted === null) {
    return { ok: false, reason: 'invalid' };
  }
  const withHold = safeMicroAdd(totalCommitted, upperBoundMicro);
  if (withHold === null || totalCommitted >= capMicro || withHold > capMicro) {
    return { ok: false, reason: 'hard_cap' };
  }

  const writable = getOrCreateDay(state, day);
  const newReserved = safeMicroAdd(writable.reservedMicro, upperBoundMicro);
  if (newReserved === null) {
    return { ok: false, reason: 'invalid' };
  }
  writable.attempts[attemptId] = {
    attemptId,
    upperBoundMicro,
    task,
    state: 'reserved',
    createdAt: new Date().toISOString(),
  };
  writable.reservedMicro = newReserved;
  return { ok: true };
}

export function reconcileAttempt(
  state: LedgerState,
  attemptId: string,
  actualUSD: number,
  task?: string
): ReconcileResult {
  const actual = costUsdToMicro(actualUSD);
  if (!attemptId || !actual.ok) {
    return { ok: false, reason: 'invalid' };
  }

  const located = findAttempt(state, attemptId);
  if (!located) {
    return { ok: false, reason: 'not_found' };
  }

  const { day, entry } = located;
  const actualMicro = actual.micro;

  if (actualMicro > MAX_SINGLE_RECONCILE_MICRO) {
    return { ok: false, reason: 'invalid' };
  }

  if (entry.state === 'reconciled' && entry.actualMicro === actualMicro) {
    return { ok: true };
  }
  if (entry.state !== 'reserved') {
    return { ok: false, reason: 'invalid' };
  }

  const newReserved = safeMicroSub(day.reservedMicro, entry.upperBoundMicro);
  const newSpent = safeMicroAdd(day.spentMicro, actualMicro);
  if (newReserved === null || newSpent === null) {
    return { ok: false, reason: 'overflow' };
  }

  const taskKey = task ?? entry.task;
  const taskTotal = safeMicroAdd(Object.hasOwn(day.tasks, taskKey) ? day.tasks[taskKey] : 0, actualMicro);
  if (taskTotal === null) {
    return { ok: false, reason: 'overflow' };
  }

  day.reservedMicro = newReserved;
  day.spentMicro = newSpent;
  day.tasks[taskKey] = taskTotal;

  const over = actualMicro > entry.upperBoundMicro;
  if (over) {
    day.overReservationCount += 1;
    entry.overReservation = true;
  }

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
      byTask: nullRecord(),
    };
  }

  const configMicro = configToMicro(config);
  const record = readDay(state, day);
  const conservativeReserved = malformedOpenReservedMicro(state);
  const byTask: Record<string, number> = nullRecord();
  for (const task of Object.keys(record.tasks)) {
    if (Object.hasOwn(record.tasks, task)) {
      byTask[task] = microToUsd(record.tasks[task]);
    }
  }

  const totalCommitted =
    conservativeReserved === null
      ? null
      : safeMicroAdd(safeMicroAdd(record.spentMicro, record.reservedMicro) ?? NaN, conservativeReserved);

  if (!configMicro.ok) {
    return {
      date: day,
      spentUSD: microToUsd(record.spentMicro),
      reservedUSD: microToUsd(record.reservedMicro),
      softThresholdReached: true,
      hardCapReached: true,
      overReservationCount: record.overReservationCount,
      byTask,
    };
  }

  const { capMicro, softMicro } = configMicro;
  return {
    date: day,
    spentUSD: microToUsd(record.spentMicro),
    reservedUSD: microToUsd(record.reservedMicro),
    softThresholdReached: totalCommitted === null ? true : totalCommitted >= softMicro,
    hardCapReached: record.spentMicro >= capMicro,
    overReservationCount: record.overReservationCount,
    byTask,
  };
}

/** Prunes eligible settled buckets; returns whether storage changed. #13-b adds unknown aging. */
export function ageLedger(state: LedgerState, now: Date): boolean {
  return pruneOldDays(state, now);
}

/** @deprecated Use {@link costUsdToMicro} for costs and {@link capUsdToMicro} for caps. */
export function usdToMicro(usd: number): number {
  const cost = costUsdToMicro(usd);
  if (cost.ok) return cost.micro;
  const cap = capUsdToMicro(usd);
  if (cap.ok) return cap.micro;
  return NaN;
}

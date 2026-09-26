/**
 * Pure spend-ledger logic (reserve / reconcile / summary / prune).
 * All monetary amounts inside the ledger are integer micro-USD (1 USD = 1_000_000 micro).
 */

import type { SpendConfig } from './types.js';

export const MICRO_USD = 1_000_000;

/** Generic sanity ceiling for configured daily caps (not a production limit). */
export const MAX_DEPLOYABLE_CAP_USD = 100;

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
  /** Set when reconcile records actual over per-attempt ceiling; locks further reserves that day. */
  hardCapLocked?: boolean;
}

export interface LedgerState {
  days: Record<string, DayRecord>;
  /** Persisted buckets that failed validation — fail-closed for that UTC day. */
  corruptDays?: Record<string, true>;
  /** Old monolith `ledger` key still present — entire DO is fail-closed until cleared. */
  legacyMonolithPresent?: true;
}

/** Retain today plus the 30 preceding UTC calendar days (31 buckets). */
export const LEDGER_DAY_BUCKETS = 31;
export const LEDGER_MAX_DAY_AGE = LEDGER_DAY_BUCKETS - 1;

/**
 * Max attempt records per UTC day bucket — sized to bound persisted record size.
 */
export const MAX_ATTEMPTS_PER_DAY = 500;

/** UUID-length attempt ids (charset unchanged). */
export const MAX_ATTEMPT_ID_LENGTH = 36;
export const MAX_TASK_NAME_LENGTH = 16;

/**
 * Worst-case JSON for one UTC day bucket must stay under this (DO per-value limit headroom).
 * Sized for 500 attempts at max id/task length and large micro-USD fields.
 */
export const MAX_BUCKET_BYTES = 100 * 1024;

/** Per-attempt reserve / reconcile USD ceiling (keeps bucket JSON bounded). */
export const MAX_ATTEMPT_USD = 1000;

const MAX_ATTEMPT_MICRO = MAX_ATTEMPT_USD * MICRO_USD;

function resolveReconcileActualMicro(
  actualUSD: number
): { ok: true; micro: number; overCeiling: boolean } | { ok: false } {
  const bounded = boundedAttemptUsdToMicro(actualUSD);
  if (bounded.ok) {
    return { ok: true, micro: bounded.micro, overCeiling: false };
  }
  if (typeof actualUSD === 'number' && Number.isFinite(actualUSD) && actualUSD > MAX_ATTEMPT_USD) {
    return { ok: true, micro: MAX_ATTEMPT_MICRO, overCeiling: true };
  }
  return { ok: false };
}

/** Max distinct task labels on one UTC day bucket (worst-case JSON sizing). */
export const MAX_DISTINCT_TASKS_PER_DAY = 32;

const DAY_KEY_RE = /^\d{4}-\d{2}-\d{2}$/;

export interface ReserveResult {
  ok: boolean;
  reason?: 'hard_cap' | 'invalid' | 'already_settled' | 'config_error' | 'attempt_limit' | 'storage_error' | 'task_limit';
}

export interface ReconcileResult {
  ok: boolean;
  reason?: 'not_found' | 'invalid' | 'overflow' | 'storage_error' | 'task_limit' | 'actual_over_ceiling';
}

export interface DaySummary {
  date: string;
  spentUSD: number;
  reservedUSD: number;
  softThresholdReached: boolean;
  hardCapReached: boolean;
  attemptLimitReached: boolean;
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

/** Reconcile actual cost: positive finite USD → safe integer micro-USD (minimum 1 micro). */
export function actualUsdToMicro(usd: number): CostMicroResult {
  if (typeof usd !== 'number' || !Number.isFinite(usd) || usd <= 0 || Object.is(usd, -0)) {
    return { ok: false };
  }
  return costUsdToMicro(usd);
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
    attemptLimitReached: true,
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

const MICRO_CEILING = Number.MAX_SAFE_INTEGER;

/** Ledger expiry uses saturating micro-USD math so stale buckets always settle and prune. */
function saturatingMicroAdd(a: number, b: number): number {
  if (!Number.isFinite(a) || !Number.isFinite(b)) {
    return MICRO_CEILING;
  }
  const sum = a + b;
  if (!Number.isFinite(sum) || sum >= MICRO_CEILING) {
    return MICRO_CEILING;
  }
  return sum;
}

function saturatingMicroSub(a: number, b: number): number {
  if (!Number.isFinite(a) || !Number.isFinite(b)) {
    return 0;
  }
  const diff = a - b;
  if (!Number.isFinite(diff) || diff <= 0) {
    return 0;
  }
  if (diff >= MICRO_CEILING) {
    return MICRO_CEILING;
  }
  return diff;
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
  return {
    days: nullRecord() as Record<string, DayRecord>,
    corruptDays: nullRecord() as Record<string, true>,
  };
}

export function markDayStorageCorrupt(state: LedgerState, day: string): void {
  if (!state.corruptDays) {
    state.corruptDays = nullRecord() as Record<string, true>;
  }
  state.corruptDays[day] = true;
  delete state.days[day];
}

export function isDayStorageCorrupt(state: LedgerState, day: string): boolean {
  return state.corruptDays !== undefined && Object.hasOwn(state.corruptDays, day);
}

export function isLegacyStorageBlocked(state: LedgerState): boolean {
  return state.legacyMonolithPresent === true;
}

/** Reserve / reconcile attempt costs above {@link MAX_ATTEMPT_USD} are rejected as invalid. */
export function boundedAttemptUsdToMicro(usd: number): CostMicroResult {
  if (typeof usd !== 'number' || !Number.isFinite(usd) || usd <= 0 || usd > MAX_ATTEMPT_USD) {
    return { ok: false };
  }
  return costUsdToMicro(usd);
}

function distinctTasksOnDay(day: DayRecord): Set<string> {
  const tasks = new Set<string>();
  for (const id of Object.keys(day.attempts)) {
    if (Object.hasOwn(day.attempts, id)) {
      tasks.add(day.attempts[id]!.task);
    }
  }
  return tasks;
}

/** Distinct task labels on a day after reconciling one attempt to taskKey. */
export function distinctTasksAfterReconcile(day: DayRecord, attemptId: string, taskKey: string): number {
  const tasks = new Set<string>();
  for (const id of Object.keys(day.attempts)) {
    if (!Object.hasOwn(day.attempts, id)) {
      continue;
    }
    tasks.add(id === attemptId ? taskKey : day.attempts[id]!.task);
  }
  return tasks.size;
}

function reserveTaskAllowedOnDay(day: DayRecord, task: string): boolean {
  const tasks = distinctTasksOnDay(day);
  if (tasks.has(task)) {
    return true;
  }
  return tasks.size < MAX_DISTINCT_TASKS_PER_DAY;
}

function reconcileTaskAllowedOnDay(day: DayRecord, attemptId: string, taskKey: string): boolean {
  return distinctTasksAfterReconcile(day, attemptId, taskKey) <= MAX_DISTINCT_TASKS_PER_DAY;
}

/** Recompute day totals from attempt rows (storage decode invariant check). */
export function recomputeDayTotalsFromAttempts(
  attempts: Record<string, AttemptEntry>
): {
  spentMicro: number;
  reservedMicro: number;
  overReservationCount: number;
  tasks: Record<string, number>;
} | null {
  let spentMicro = 0;
  let reservedMicro = 0;
  let overReservationCount = 0;
  const tasks = nullRecord() as Record<string, number>;
  for (const id of Object.keys(attempts)) {
    if (!Object.hasOwn(attempts, id)) {
      continue;
    }
    const entry = attempts[id]!;
    if (entry.state === 'reserved' || entry.state === 'unknown') {
      const next = safeMicroAdd(reservedMicro, entry.upperBoundMicro);
      if (next === null) {
        return null;
      }
      reservedMicro = next;
      continue;
    }
    if (entry.state !== 'reconciled') {
      return null;
    }
    if (entry.actualMicro === undefined) {
      return null;
    }
    const nextSpent = safeMicroAdd(spentMicro, entry.actualMicro);
    if (nextSpent === null) {
      return null;
    }
    spentMicro = nextSpent;
    const prevTask = Object.hasOwn(tasks, entry.task) ? tasks[entry.task]! : 0;
    const nextTask = safeMicroAdd(prevTask, entry.actualMicro);
    if (nextTask === null) {
      return null;
    }
    tasks[entry.task] = nextTask;
    if (entry.overReservation === true || entry.actualMicro > entry.upperBoundMicro) {
      overReservationCount += 1;
    }
  }
  return { spentMicro, reservedMicro, overReservationCount, tasks };
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

/** Rebuild maps with null prototypes after JSON storage reload (avoids prototype-key collisions). */
export function hydrateDayRecord(raw: DayRecord): DayRecord {
  const attempts = nullRecord() as Record<string, AttemptEntry>;
  for (const key of Object.keys(raw.attempts ?? {})) {
    if (Object.hasOwn(raw.attempts, key)) {
      attempts[key] = raw.attempts[key]!;
    }
  }
  const tasks = nullRecord() as Record<string, number>;
  for (const key of Object.keys(raw.tasks ?? {})) {
    if (Object.hasOwn(raw.tasks, key)) {
      tasks[key] = raw.tasks[key]!;
    }
  }
  return {
    date: raw.date,
    spentMicro: raw.spentMicro,
    reservedMicro: raw.reservedMicro,
    overReservationCount: raw.overReservationCount,
    attempts,
    tasks,
    hardCapLocked: raw.hardCapLocked === true,
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

/** Valid ledger day for new reserves: server's current UTC calendar day only. */
export function isLedgerDayKeyUsable(day: string, now: Date): boolean {
  if (!isValidLedgerDayKey(day)) {
    return false;
  }
  return utcDayAgeDays(day, now) === 0;
}

const UNSAFE_TASK_NAMES = new Set(['__proto__', 'constructor', 'prototype']);
const ATTEMPT_ID_RE = new RegExp(`^[A-Za-z0-9_-]{1,${MAX_ATTEMPT_ID_LENGTH}}$`);
const TASK_NAME_RE = new RegExp(`^[A-Za-z0-9_-]{1,${MAX_TASK_NAME_LENGTH}}$`);

export function isValidAttemptId(attemptId: string): boolean {
  return typeof attemptId === 'string' && ATTEMPT_ID_RE.test(attemptId);
}

export function isValidReserveTaskName(task: string): boolean {
  return (
    typeof task === 'string' &&
    TASK_NAME_RE.test(task) &&
    !UNSAFE_TASK_NAMES.has(task)
  );
}

function isProtectedBucketEvictionWindow(key: string, now: Date): boolean {
  if (!isValidLedgerDayKey(key)) {
    return false;
  }
  const age = utcDayAgeDays(key, now);
  return age >= -1 && age <= LEDGER_MAX_DAY_AGE;
}

function enforceBucketLimit(state: LedgerState, now: Date): void {
  const deletable = Object.keys(state.days)
    .filter((key) => {
      const day = state.days[key];
      if (dayHasOpenAttempts(day) || !dayIsFullySettled(day)) {
        return false;
      }
      if (isProtectedBucketEvictionWindow(key, now)) {
        return false;
      }
      return true;
    })
    .sort((a, b) => {
      const ageA = isValidLedgerDayKey(a) ? utcDayAgeDays(a, now) : Number.MAX_SAFE_INTEGER;
      const ageB = isValidLedgerDayKey(b) ? utcDayAgeDays(b, now) : Number.MAX_SAFE_INTEGER;
      return ageB - ageA;
    });

  for (const key of deletable) {
    delete state.days[key];
  }
}

/** Settled buckets outside today−30…today+1 (used to prove age-based retention). */
export function countSettledBucketsOutsideEvictionWindow(state: LedgerState, now: Date): number {
  let count = 0;
  for (const key of Object.keys(state.days)) {
    if (isProtectedBucketEvictionWindow(key, now)) {
      continue;
    }
    if (dayIsFullySettled(state.days[key])) {
      count += 1;
    }
  }
  return count;
}

function dayAttemptCount(day: DayRecord): number {
  return Object.keys(day.attempts).length;
}

function attemptLimitReachedForDay(day: DayRecord): boolean {
  return dayAttemptCount(day) >= MAX_ATTEMPTS_PER_DAY;
}

/** Conservatively settle open attempts on days older than today−30 (full upper bound). */
function expireStaleOpenAttempts(state: LedgerState, now: Date): boolean {
  let changed = false;
  for (const key of Object.keys(state.days)) {
    if (!isValidLedgerDayKey(key)) {
      continue;
    }
    if (utcDayAgeDays(key, now) <= LEDGER_MAX_DAY_AGE) {
      continue;
    }
    const day = state.days[key];
    for (const entry of Object.values(day.attempts)) {
      if (entry.state !== 'reserved' && entry.state !== 'unknown') {
        continue;
      }
      const settleMicro = entry.upperBoundMicro;
      day.reservedMicro = saturatingMicroSub(day.reservedMicro, settleMicro);
      day.spentMicro = saturatingMicroAdd(day.spentMicro, settleMicro);
      const taskPrev = Object.hasOwn(day.tasks, entry.task) ? day.tasks[entry.task]! : 0;
      day.tasks[entry.task] = saturatingMicroAdd(taskPrev, settleMicro);
      entry.state = 'reconciled';
      entry.actualMicro = settleMicro;
      entry.reconciledAt = new Date().toISOString();
      changed = true;
    }
  }
  return changed;
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
 * Prune fully settled buckets older than the protected UTC window. Open attempts on days
 * older than today−30 are conservatively settled at their reserved upper bound first.
 */
export function pruneOldDays(state: LedgerState, now: Date): boolean {
  const keysBefore = Object.keys(state.days).sort().join('\0');
  expireStaleOpenAttempts(state, now);
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
    if (age > LEDGER_MAX_DAY_AGE) {
      delete state.days[key];
      continue;
    }
  }
  enforceBucketLimit(state, now);
  const keysAfter = Object.keys(state.days).sort().join('\0');
  return keysBefore !== keysAfter;
}

function findAttempt(
  state: LedgerState,
  dayKey: string,
  attemptId: string
): { day: DayRecord; entry: AttemptEntry } | null {
  const day = state.days[dayKey];
  if (!day) {
    return null;
  }
  if (!Object.hasOwn(day.attempts, attemptId)) {
    return null;
  }
  const entry = day.attempts[attemptId]!;
  return { day, entry };
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
  if (isLegacyStorageBlocked(state)) {
    return { ok: false, reason: 'storage_error' };
  }
  if (isDayStorageCorrupt(state, day)) {
    return { ok: false, reason: 'storage_error' };
  }
  if (readDay(state, day).hardCapLocked) {
    return { ok: false, reason: 'hard_cap' };
  }
  const bounds = boundedAttemptUsdToMicro(upperBoundUSD);
  if (!isValidAttemptId(attemptId) || !bounds.ok) {
    return { ok: false, reason: 'invalid' };
  }
  const upperBoundMicro = bounds.micro;

  const existingOnDay = findAttempt(state, day, attemptId);
  if (existingOnDay) {
    if (existingOnDay.entry.state === 'reconciled' || existingOnDay.entry.state === 'unknown') {
      return { ok: false, reason: 'already_settled' };
    }
    if (existingOnDay.entry.upperBoundMicro === upperBoundMicro) {
      return { ok: true };
    }
    return { ok: false, reason: 'invalid' };
  }

  if (!isLedgerDayKeyUsable(day, now)) {
    return { ok: false, reason: 'invalid' };
  }
  if (!isValidReserveTaskName(task)) {
    return { ok: false, reason: 'invalid' };
  }

  const dayRecordForTask = readDay(state, day);
  if (!reserveTaskAllowedOnDay(dayRecordForTask, task)) {
    return { ok: false, reason: 'task_limit' };
  }

  const configMicro = configToMicro(config);
  if (!configMicro.ok) {
    return { ok: false, reason: 'config_error' };
  }
  const { capMicro } = configMicro;

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
  if (attemptLimitReachedForDay(writable)) {
    return { ok: false, reason: 'attempt_limit' };
  }
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
  day: string,
  attemptId: string,
  actualUSD: number,
  task?: string
): ReconcileResult {
  if (isLegacyStorageBlocked(state)) {
    return { ok: false, reason: 'storage_error' };
  }
  if (isDayStorageCorrupt(state, day)) {
    return { ok: false, reason: 'storage_error' };
  }
  if (!isValidLedgerDayKey(day)) {
    return { ok: false, reason: 'invalid' };
  }
  if (task !== undefined && !isValidReserveTaskName(task)) {
    return { ok: false, reason: 'invalid' };
  }
  const resolvedActual = resolveReconcileActualMicro(actualUSD);
  if (!isValidAttemptId(attemptId) || !resolvedActual.ok) {
    return { ok: false, reason: 'invalid' };
  }

  const located = findAttempt(state, day, attemptId);
  if (!located) {
    return { ok: false, reason: 'not_found' };
  }

  const { day: dayRecord, entry } = located;
  const { micro: actualMicro, overCeiling: actualOverCeiling } = resolvedActual;

  if (entry.state === 'reconciled') {
    if (actualOverCeiling && dayRecord.hardCapLocked && entry.actualMicro === MAX_ATTEMPT_MICRO) {
      return { ok: false, reason: 'actual_over_ceiling' };
    }
    if (!actualOverCeiling && entry.actualMicro === actualMicro) {
      return { ok: true };
    }
    return { ok: false, reason: 'invalid' };
  }
  if (entry.state !== 'reserved') {
    return { ok: false, reason: 'invalid' };
  }

  const taskKey = task ?? entry.task;
  if (!reconcileTaskAllowedOnDay(dayRecord, attemptId, taskKey)) {
    return { ok: false, reason: 'task_limit' };
  }

  const newReserved = safeMicroSub(dayRecord.reservedMicro, entry.upperBoundMicro);
  const newSpent = safeMicroAdd(dayRecord.spentMicro, actualMicro);
  if (newReserved === null || newSpent === null) {
    return { ok: false, reason: 'overflow' };
  }

  const taskTotal = safeMicroAdd(
    Object.hasOwn(dayRecord.tasks, taskKey) ? dayRecord.tasks[taskKey] : 0,
    actualMicro
  );
  if (taskTotal === null) {
    return { ok: false, reason: 'overflow' };
  }

  dayRecord.reservedMicro = newReserved;
  dayRecord.spentMicro = newSpent;
  dayRecord.tasks[taskKey] = taskTotal;

  const over = actualMicro > entry.upperBoundMicro || actualOverCeiling;
  if (over) {
    dayRecord.overReservationCount += 1;
    entry.overReservation = true;
  }
  if (actualOverCeiling) {
    dayRecord.hardCapLocked = true;
  }

  entry.state = 'reconciled';
  entry.actualMicro = actualMicro;
  entry.task = taskKey;
  entry.reconciledAt = new Date().toISOString();
  if (actualOverCeiling) {
    return { ok: false, reason: 'actual_over_ceiling' };
  }
  return { ok: true };
}

export function summarizeDay(
  state: LedgerState,
  day: string,
  config: SpendConfig
): DaySummary {
  if (isLegacyStorageBlocked(state)) {
    return failClosedDaySummary(day);
  }
  if (isDayStorageCorrupt(state, day)) {
    return failClosedDaySummary(day);
  }
  if (!isValidLedgerDayKey(day)) {
    return {
      date: day,
      spentUSD: 0,
      reservedUSD: 0,
      softThresholdReached: false,
      hardCapReached: false,
      attemptLimitReached: false,
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
      attemptLimitReached: attemptLimitReachedForDay(record),
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
    hardCapReached: dayHardCapReached(state, day, capMicro),
    attemptLimitReached: attemptLimitReachedForDay(record),
    overReservationCount: record.overReservationCount,
    byTask,
  };
}

/** True when {@link reserveAttempt} would refuse another hold with `hard_cap` (minimum 1 micro-USD). */
export function dayHardCapReached(state: LedgerState, day: string, capMicro: number): boolean {
  const record = readDay(state, day);
  if (record.hardCapLocked) {
    return true;
  }
  if (record.spentMicro >= capMicro) {
    return true;
  }
  const conservativeReserved = malformedOpenReservedMicro(state);
  if (conservativeReserved === null) {
    return true;
  }
  const spentPlusReserved = safeMicroAdd(record.spentMicro, record.reservedMicro);
  if (spentPlusReserved === null) {
    return true;
  }
  const totalCommitted = safeMicroAdd(spentPlusReserved, conservativeReserved);
  if (totalCommitted === null) {
    return true;
  }
  const withMinHold = safeMicroAdd(totalCommitted, 1);
  return withMinHold === null || totalCommitted >= capMicro || withMinHold > capMicro;
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

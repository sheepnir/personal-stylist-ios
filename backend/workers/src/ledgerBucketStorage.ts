/**
 * Per-UTC-day bucket keys for DeviceSpendLedger (#13-a storage bound).
 */

import {
  emptyLedgerState,
  hydrateDayRecord,
  isValidAttemptId,
  isValidLedgerDayKey,
  isValidReserveTaskName,
  markDayStorageCorrupt,
  isDayStorageCorrupt,
  MAX_BUCKET_BYTES,
  recomputeDayTotalsFromAttempts,
  type AttemptEntry,
  type AttemptState,
  type DayRecord,
  type LedgerState,
} from './ledgerCore.js';

export const BUCKET_KEY_PREFIX = 'bucket:';
const LEGACY_LEDGER_KEY = 'ledger';

const STATE_CODES = new Set([0, 1, 2]);

/** JavaScript Date-safe epoch milliseconds (inclusive upper bound). */
const MAX_LEDGER_EPOCH_MS = 8_640_000_000_000_000;

/** Compact persisted attempt (attempt id is the map key). */
interface StoredAttempt {
  u: number;
  t: string;
  S: 0 | 1 | 2;
  a?: number;
  c: number;
  R?: number;
  O?: 1;
}

/** Compact persisted day bucket JSON shape (under MAX_BUCKET_BYTES at 500 attempts). */
interface StoredDayBucket {
  s: number;
  r: number;
  o: number;
  a: Record<string, StoredAttempt>;
  k: Record<string, number>;
  /** Hard-cap lock marker (1) after actual-over-ceiling reconcile. */
  H?: 1;
}

const STATE_TO_CODE: Record<AttemptState, 0 | 1 | 2> = {
  reserved: 0,
  reconciled: 1,
  unknown: 2,
};

const CODE_TO_STATE: Record<0 | 1 | 2, AttemptState> = {
  0: 'reserved',
  1: 'reconciled',
  2: 'unknown',
};

function isNonNegativeSafeInt(value: unknown): value is number {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= 0;
}

function isEpochMs(value: unknown): value is number {
  return (
    typeof value === 'number' &&
    Number.isSafeInteger(value) &&
    value >= 0 &&
    value <= MAX_LEDGER_EPOCH_MS
  );
}

function validateStoredAttempt(id: string, raw: unknown): StoredAttempt | null {
  if (!isValidAttemptId(id) || typeof raw !== 'object' || raw === null) {
    return null;
  }
  const a = raw as Record<string, unknown>;
  if (!isNonNegativeSafeInt(a.u) || typeof a.t !== 'string' || !isValidReserveTaskName(a.t)) {
    return null;
  }
  const stateCode = a.S as number;
  if (!STATE_CODES.has(stateCode)) {
    return null;
  }
  if (!isEpochMs(a.c)) {
    return null;
  }
  if (stateCode === 0 || stateCode === 2) {
    if (a.a !== undefined || a.R !== undefined) {
      return null;
    }
  } else if (!isNonNegativeSafeInt(a.a)) {
    return null;
  }
  if (a.R !== undefined && !isEpochMs(a.R)) {
    return null;
  }
  if (a.O !== undefined && a.O !== 1) {
    return null;
  }
  return raw as StoredAttempt;
}

/** Strict validation of persisted compact bucket JSON; null when malformed. */
export function validateStoredDayBucket(raw: unknown): StoredDayBucket | null {
  if (typeof raw !== 'object' || raw === null || 'attempts' in raw) {
    return null;
  }
  const top = raw as Record<string, unknown>;
  if (!isNonNegativeSafeInt(top.s) || !isNonNegativeSafeInt(top.r) || !isNonNegativeSafeInt(top.o)) {
    return null;
  }
  if (top.H !== undefined && top.H !== 1) {
    return null;
  }
  if (typeof top.a !== 'object' || top.a === null || typeof top.k !== 'object' || top.k === null) {
    return null;
  }
  const attemptsRaw = top.a as Record<string, unknown>;
  const attempts = Object.create(null) as Record<string, StoredAttempt>;
  for (const id of Object.keys(attemptsRaw)) {
    if (!Object.hasOwn(attemptsRaw, id)) {
      continue;
    }
    const attempt = validateStoredAttempt(id, attemptsRaw[id]);
    if (!attempt) {
      return null;
    }
    attempts[id] = attempt;
  }
  const tasksRaw = top.k as Record<string, unknown>;
  const tasks = Object.create(null) as Record<string, number>;
  for (const task of Object.keys(tasksRaw)) {
    if (!Object.hasOwn(tasksRaw, task)) {
      continue;
    }
    if (!isValidReserveTaskName(task) || !isNonNegativeSafeInt(tasksRaw[task])) {
      return null;
    }
    tasks[task] = tasksRaw[task] as number;
  }
  return { s: top.s, r: top.r, o: top.o, a: attempts, k: tasks, ...(top.H === 1 ? { H: 1 as const } : {}) };
}

export function parseBucketStorageKey(key: string): string | null {
  if (!key.startsWith(BUCKET_KEY_PREFIX)) {
    return null;
  }
  const day = key.slice(BUCKET_KEY_PREFIX.length);
  return isValidLedgerDayKey(day) ? day : null;
}

function encodeAttempt(entry: AttemptEntry): StoredAttempt {
  const stored: StoredAttempt = {
    u: entry.upperBoundMicro,
    t: entry.task,
    S: STATE_TO_CODE[entry.state],
    c: Date.parse(entry.createdAt),
  };
  if (entry.actualMicro !== undefined) {
    stored.a = entry.actualMicro;
  }
  if (entry.reconciledAt !== undefined) {
    stored.R = Date.parse(entry.reconciledAt);
  }
  if (entry.overReservation) {
    stored.O = 1;
  }
  return stored;
}

export function encodeDayForStorage(day: DayRecord): StoredDayBucket {
  const a: Record<string, StoredAttempt> = Object.create(null);
  for (const id of Object.keys(day.attempts)) {
    if (Object.hasOwn(day.attempts, id)) {
      a[id] = encodeAttempt(day.attempts[id]!);
    }
  }
  const k: Record<string, number> = Object.create(null);
  for (const task of Object.keys(day.tasks)) {
    if (Object.hasOwn(day.tasks, task)) {
      k[task] = day.tasks[task]!;
    }
  }
  return {
    s: day.spentMicro,
    r: day.reservedMicro,
    o: day.overReservationCount,
    a,
    k,
    ...(day.hardCapLocked ? { H: 1 as const } : {}),
  };
}

function decodeAttempt(id: string, stored: StoredAttempt): AttemptEntry {
  const entry: AttemptEntry = {
    attemptId: id,
    upperBoundMicro: stored.u,
    task: stored.t,
    state: CODE_TO_STATE[stored.S],
    createdAt: new Date(stored.c).toISOString(),
  };
  if (stored.a !== undefined) {
    entry.actualMicro = stored.a;
  }
  if (stored.R !== undefined) {
    entry.reconciledAt = new Date(stored.R).toISOString();
  }
  if (stored.O) {
    entry.overReservation = true;
  }
  return entry;
}

function storedTasksMatchRecomputed(
  stored: Record<string, number>,
  recomputed: Record<string, number>
): boolean {
  const storedKeys = Object.keys(stored);
  const recomputedKeys = Object.keys(recomputed);
  if (storedKeys.length !== recomputedKeys.length) {
    return false;
  }
  for (const task of storedKeys) {
    if (!Object.hasOwn(stored, task) || stored[task] !== recomputed[task]) {
      return false;
    }
  }
  return true;
}

/** Decode one day bucket; null when attempts disagree with stored totals or decode throws. */
export function decodeDayFromStorage(date: string, stored: StoredDayBucket): DayRecord | null {
  try {
    const attempts = Object.create(null) as Record<string, AttemptEntry>;
    for (const id of Object.keys(stored.a)) {
      if (Object.hasOwn(stored.a, id)) {
        attempts[id] = decodeAttempt(id, stored.a[id]!);
      }
    }
    const recomputed = recomputeDayTotalsFromAttempts(attempts);
    if (recomputed === null) {
      return null;
    }
    if (
      recomputed.spentMicro !== stored.s ||
      recomputed.reservedMicro !== stored.r ||
      recomputed.overReservationCount !== stored.o ||
      !storedTasksMatchRecomputed(stored.k, recomputed.tasks)
    ) {
      return null;
    }
    return hydrateDayRecord({
      date,
      spentMicro: recomputed.spentMicro,
      reservedMicro: recomputed.reservedMicro,
      overReservationCount: recomputed.overReservationCount,
      attempts,
      tasks: recomputed.tasks,
      hardCapLocked: stored.H === 1,
    });
  } catch {
    return null;
  }
}

/** UTF-8 byte length of the compact JSON persisted for one day bucket. */
export function storedDayBucketJsonByteLength(day: DayRecord): number {
  return new TextEncoder().encode(JSON.stringify(encodeDayForStorage(day))).length;
}

export function bucketStorageKey(day: string): string {
  return `${BUCKET_KEY_PREFIX}${day}`;
}

type ListableKv = {
  list: (options?: { prefix?: string }) => Iterable<[string, unknown]>;
};

type ReadableKv = ListableKv & {
  get: <T>(key: string) => T | undefined;
};

type WritableKv = ReadableKv & {
  put: (key: string, value: unknown) => void;
  delete: (key: string) => void;
};

function listValidBucketDaysFromStorage(kv: ListableKv): string[] {
  const days: string[] = [];
  for (const [name] of kv.list({ prefix: BUCKET_KEY_PREFIX })) {
    const day = parseBucketStorageKey(name);
    if (day) {
      days.push(day);
      continue;
    }
    if (name.startsWith(BUCKET_KEY_PREFIX)) {
      console.warn(`DeviceSpendLedger: ignoring invalid bucket storage key ${name}`);
    }
  }
  return days;
}

/** Day keys present in storage before a transaction (valid bucket keys + legacy monolith days). */
export function dayKeysInStorage(kv: ReadableKv): Set<string> {
  const keys = new Set(listValidBucketDaysFromStorage(kv));
  const legacy = kv.get<LedgerState>(LEGACY_LEDGER_KEY);
  if (legacy?.days) {
    for (const day of Object.keys(legacy.days)) {
      if (isValidLedgerDayKey(day)) {
        keys.add(day);
      }
    }
  }
  return keys;
}

function loadStoredDayBucket(kv: ReadableKv, day: string, state: LedgerState): void {
  const raw = kv.get<unknown>(bucketStorageKey(day));
  if (raw === undefined) {
    return;
  }
  const stored = validateStoredDayBucket(raw);
  if (!stored) {
    markDayStorageCorrupt(state, day);
    return;
  }
  const decoded = decodeDayFromStorage(day, stored);
  if (!decoded) {
    markDayStorageCorrupt(state, day);
    return;
  }
  state.days[day] = decoded;
}

export function loadLedgerFromStorage(kv: ReadableKv): LedgerState {
  const state = emptyLedgerState();
  const legacy = kv.get<unknown>(LEGACY_LEDGER_KEY);
  if (legacy !== undefined && legacy !== null && typeof legacy === 'object' && 'days' in legacy) {
    const daysRaw = (legacy as { days?: unknown }).days;
    if (daysRaw !== null && typeof daysRaw === 'object') {
      for (const [day, record] of Object.entries(daysRaw as Record<string, unknown>)) {
        if (!isValidLedgerDayKey(day)) {
          continue;
        }
        try {
          if (record === null || typeof record !== 'object') {
            markDayStorageCorrupt(state, day);
            continue;
          }
          const encoded = validateStoredDayBucket(encodeDayForStorage(hydrateDayRecord(record as DayRecord)));
          if (!encoded) {
            markDayStorageCorrupt(state, day);
            continue;
          }
          const decoded = decodeDayFromStorage(day, encoded);
          if (!decoded) {
            markDayStorageCorrupt(state, day);
          } else {
            state.days[day] = decoded;
          }
        } catch {
          markDayStorageCorrupt(state, day);
        }
      }
    }
  }
  for (const day of listValidBucketDaysFromStorage(kv)) {
    loadStoredDayBucket(kv, day, state);
  }
  return state;
}

/** Write touched day buckets; delete pruned days and drop the legacy monolith key. */
export type PersistLedgerResult = { ok: true } | { ok: false; reason: 'bucket_too_large' };

export function persistLedgerToStorage(
  kv: WritableKv,
  state: LedgerState,
  dayKeysBefore: Set<string>
): PersistLedgerResult {
  for (const day of Object.keys(state.days)) {
    if (storedDayBucketJsonByteLength(state.days[day]!) > MAX_BUCKET_BYTES) {
      return { ok: false, reason: 'bucket_too_large' };
    }
  }
  kv.delete(LEGACY_LEDGER_KEY);
  const dayKeysAfter = new Set(Object.keys(state.days));
  for (const day of dayKeysBefore) {
    if (!dayKeysAfter.has(day) && !isDayStorageCorrupt(state, day)) {
      kv.delete(bucketStorageKey(day));
    }
  }
  for (const day of dayKeysAfter) {
    kv.put(bucketStorageKey(day), encodeDayForStorage(state.days[day]!));
  }
  return { ok: true };
}

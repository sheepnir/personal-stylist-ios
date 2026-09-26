/**
 * Per-UTC-day bucket keys for DeviceSpendLedger (#13-a storage bound).
 */

import {
  emptyLedgerState,
  hydrateDayRecord,
  type AttemptEntry,
  type AttemptState,
  type DayRecord,
  type LedgerState,
} from './ledgerCore.js';

export const BUCKET_KEY_PREFIX = 'bucket:';
const LEGACY_LEDGER_KEY = 'ledger';

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

function isStoredDayBucket(raw: unknown): raw is StoredDayBucket {
  return (
    typeof raw === 'object' &&
    raw !== null &&
    'a' in raw &&
    'k' in raw &&
    !('attempts' in raw)
  );
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

export function decodeDayFromStorage(date: string, stored: StoredDayBucket): DayRecord {
  const attempts = Object.create(null) as Record<string, AttemptEntry>;
  for (const id of Object.keys(stored.a)) {
    if (Object.hasOwn(stored.a, id)) {
      attempts[id] = decodeAttempt(id, stored.a[id]!);
    }
  }
  const tasks = Object.create(null) as Record<string, number>;
  for (const task of Object.keys(stored.k)) {
    if (Object.hasOwn(stored.k, task)) {
      tasks[task] = stored.k[task]!;
    }
  }
  return hydrateDayRecord({
    date,
    spentMicro: stored.s,
    reservedMicro: stored.r,
    overReservationCount: stored.o,
    attempts,
    tasks,
  });
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

export function listStoredDayKeys(kv: ListableKv): string[] {
  const days: string[] = [];
  for (const [name] of kv.list({ prefix: BUCKET_KEY_PREFIX })) {
    days.push(name.slice(BUCKET_KEY_PREFIX.length));
  }
  return days;
}

/** Day keys present in storage before a transaction (bucket keys + legacy monolith days). */
export function dayKeysInStorage(kv: ReadableKv): Set<string> {
  const keys = new Set(listStoredDayKeys(kv));
  const legacy = kv.get<LedgerState>(LEGACY_LEDGER_KEY);
  if (legacy?.days) {
    for (const day of Object.keys(legacy.days)) {
      keys.add(day);
    }
  }
  return keys;
}

function decodeStoredBucket(day: string, raw: unknown): DayRecord {
  if (isStoredDayBucket(raw)) {
    return decodeDayFromStorage(day, raw);
  }
  return hydrateDayRecord(raw as DayRecord);
}

export function loadLedgerFromStorage(kv: ReadableKv): LedgerState {
  const state = emptyLedgerState();
  const legacy = kv.get<LedgerState>(LEGACY_LEDGER_KEY);
  if (legacy?.days) {
    for (const [day, record] of Object.entries(legacy.days)) {
      state.days[day] = hydrateDayRecord(record);
    }
  }
  for (const day of listStoredDayKeys(kv)) {
    const raw = kv.get<unknown>(bucketStorageKey(day));
    if (raw) {
      state.days[day] = decodeStoredBucket(day, raw);
    }
  }
  return state;
}

/** Write touched day buckets; delete pruned days and drop the legacy monolith key. */
export function persistLedgerToStorage(kv: WritableKv, state: LedgerState, dayKeysBefore: Set<string>): void {
  kv.delete(LEGACY_LEDGER_KEY);
  const dayKeysAfter = new Set(Object.keys(state.days));
  for (const day of dayKeysBefore) {
    if (!dayKeysAfter.has(day)) {
      kv.delete(bucketStorageKey(day));
    }
  }
  for (const day of dayKeysAfter) {
    kv.put(bucketStorageKey(day), encodeDayForStorage(state.days[day]!));
  }
}

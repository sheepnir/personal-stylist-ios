/**
 * Persisted bucket validation and storage-key safety.
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import {
  MAX_ATTEMPT_USD,
  MAX_ATTEMPTS_PER_DAY,
  MAX_BUCKET_BYTES,
  MICRO_USD,
  emptyLedgerState,
  isDayStorageCorrupt,
  markDayStorageCorrupt,
  reconcileAttempt,
  reserveAttempt,
} from '../src/ledgerCore.js';
import {
  bucketStorageKey,
  loadLedgerFromStorage,
  parseBucketStorageKey,
  persistLedgerToStorage,
  storedDayBucketJsonByteLength,
  storedDayBucketViolatesLedgerLimits,
  validateStoredDayBucket,
} from '../src/ledgerBucketStorage.js';
import { createDeviceSpendLedgerHarness } from './helpers.js';
import type { DayRecord } from '../src/ledgerCore.js';
import { worstCaseAttemptId } from './ledgerCore.bucketBytes.test.js';

const DAY = '2026-09-26';
const CONFIG = { dailyCapUSD: 10_000, softThresholdUSD: 5000 };
const NOW = new Date(`${DAY}T12:00:00.000Z`);

function memoryKv(initial: Record<string, unknown> = {}) {
  const store = new Map<string, unknown>(Object.entries(initial));
  return {
    get: <T>(key: string) => store.get(key) as T | undefined,
    put: (key: string, value: unknown) => {
      store.set(key, value);
    },
    delete: (key: string) => {
      store.delete(key);
    },
    list: (options?: { prefix?: string }) => {
      const prefix = options?.prefix ?? '';
      const entries: [string, unknown][] = [];
      for (const [name, value] of store) {
        if (name.startsWith(prefix)) {
          entries.push([name, value]);
        }
      }
      return entries;
    },
  };
}

describe('validateStoredDayBucket', () => {
  const validBase = {
    s: 0,
    r: 0,
    o: 0,
    a: {},
    k: {},
  };

  it('rejects negative spent micro (s)', () => {
    expect(validateStoredDayBucket({ ...validBase, s: -1 })).toBeNull();
  });

  it('rejects fractional spent micro', () => {
    expect(validateStoredDayBucket({ ...validBase, s: 1.5 })).toBeNull();
  });

  it('rejects unsafe integer spent micro', () => {
    expect(validateStoredDayBucket({ ...validBase, s: Number.MAX_SAFE_INTEGER + 1 })).toBeNull();
  });

  it('rejects unknown attempt state code', () => {
    expect(
      validateStoredDayBucket({
        ...validBase,
        a: {
          ok: { u: 1, t: 'generate', S: 9, c: 0 },
        },
      })
    ).toBeNull();
  });

  it('rejects attempt task when t is missing or not a string', () => {
    expect(
      validateStoredDayBucket({
        ...validBase,
        a: { bad: { u: 1, S: 0, c: 0 } },
      })
    ).toBeNull();
  });
});

describe('loadLedgerFromStorage fail-closed', () => {
  beforeEach(() => {
    vi.useFakeTimers({ now: NOW });
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it('marks a malformed bucket corrupt and refuses new reserves', () => {
    const kv = memoryKv({
      [bucketStorageKey(DAY)]: { s: -1, r: 0, o: 0, a: {}, k: {} },
    });
    const state = loadLedgerFromStorage(kv);
    expect(isDayStorageCorrupt(state, DAY)).toBe(true);
    expect(state.days[DAY]).toBeUndefined();
    expect(reserveAttempt(state, 'new', 0.1, DAY, CONFIG, 'generate', NOW)).toEqual({
      ok: false,
      reason: 'storage_error',
    });
  });

  it('ignores bucket:__proto__ keys without polluting state.days', () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const kv = memoryKv({
      'bucket:__proto__': { s: 0, r: 0, o: 0, a: {}, k: {} },
      [bucketStorageKey(DAY)]: { s: 0, r: 0, o: 0, a: {}, k: {} },
    });
    const state = loadLedgerFromStorage(kv);
    expect(parseBucketStorageKey('bucket:__proto__')).toBeNull();
    expect(state.days.__proto__).toBeUndefined();
    expect(Object.hasOwn(state.days, '__proto__')).toBe(false);
    expect(warn).toHaveBeenCalled();
    warn.mockRestore();
  });

  it('marks day corrupt when stored reserved total disagrees with open holds (r:0, open u)', () => {
    const createdMs = Date.parse(`${DAY}T01:00:00.000Z`);
    const kv = memoryKv({
      [bucketStorageKey(DAY)]: {
        s: 0,
        r: 0,
        o: 0,
        a: {
          openhold: { u: 1_000_000, t: 'generate', S: 0, c: createdMs },
        },
        k: {},
      },
    });
    const state = loadLedgerFromStorage(kv);
    expect(isDayStorageCorrupt(state, DAY)).toBe(true);
    expect(reserveAttempt(state, 'new', 0.1, DAY, CONFIG, 'generate', NOW)).toEqual({
      ok: false,
      reason: 'storage_error',
    });
  });

  it('marks day corrupt when stored spent disagrees with reconciled attempts', () => {
    const createdMs = Date.parse(`${DAY}T01:00:00.000Z`);
    const kv = memoryKv({
      [bucketStorageKey(DAY)]: {
        s: 9_999_999,
        r: 0,
        o: 0,
        a: {
          settled1: { u: 1_000_000, t: 'generate', S: 1, a: 1_000_000, c: createdMs },
        },
        k: { generate: 1_000_000 },
      },
    });
    const state = loadLedgerFromStorage(kv);
    expect(isDayStorageCorrupt(state, DAY)).toBe(true);
  });

  it('marks day corrupt when stored byTask disagrees with reconciled attempts', () => {
    const createdMs = Date.parse(`${DAY}T01:00:00.000Z`);
    const kv = memoryKv({
      [bucketStorageKey(DAY)]: {
        s: 1_000_000,
        r: 0,
        o: 0,
        a: {
          settled1: { u: 1_000_000, t: 'generate', S: 1, a: 1_000_000, c: createdMs },
        },
        k: { generate: 2_000_000 },
      },
    });
    const state = loadLedgerFromStorage(kv);
    expect(isDayStorageCorrupt(state, DAY)).toBe(true);
  });

  it('marks day corrupt when attempt created epoch exceeds Date-safe range', () => {
    const kv = memoryKv({
      [bucketStorageKey(DAY)]: {
        s: 0,
        r: 0,
        o: 0,
        a: {
          badtime: { u: 1, t: 'generate', S: 0, c: 9_000_000_000_000_000 },
        },
        k: {},
      },
    });
    const state = loadLedgerFromStorage(kv);
    expect(isDayStorageCorrupt(state, DAY)).toBe(true);
  });
});

describe('legacy monolith key fail-closed', () => {
  beforeEach(() => {
    vi.useFakeTimers({ now: NOW });
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it('blocks the entire DO while the ledger key remains untouched after writes', () => {
    const legacyPayload = {
      days: {
        [DAY]: {
          date: DAY,
          spentMicro: 0,
          reservedMicro: 0,
          overReservationCount: 0,
          attempts: Object.create(null),
          tasks: Object.create(null),
        },
      },
    };
    const { ledger, kvHas } = createDeviceSpendLedgerHarness(undefined, {
      initialKv: { ledger: legacyPayload },
    });
    expect(loadLedgerFromStorage(memoryKv({ ledger: legacyPayload })).legacyMonolithPresent).toBe(true);
    expect(ledger.reserve('blocked', 0.01, DAY, CONFIG, 'generate')).toEqual({
      ok: false,
      reason: 'storage_error',
    });
    expect(ledger.reconcile(DAY, 'blocked', 0.01)).toEqual({ ok: false, reason: 'storage_error' });
    const summary = ledger.summary(DAY, CONFIG);
    expect(summary.hardCapReached).toBe(true);
    expect(summary.attemptLimitReached).toBe(true);
    expect(kvHas('ledger')).toBe(true);
  });

  it('legacy repro: corrupt ledger today plus reserve stays fail-closed and never deletes ledger', () => {
    const legacyPayload = {
      days: {
        [DAY]: null,
        '2026-09-25': {
          date: '2026-09-25',
          spentMicro: 0,
          reservedMicro: 0,
          overReservationCount: 0,
          attempts: Object.create(null),
          tasks: Object.create(null),
        },
      },
    };
    const tomorrow = '2026-09-27';
    const { ledger, kvHas } = createDeviceSpendLedgerHarness(undefined, {
      initialKv: { ledger: legacyPayload },
    });
    expect(ledger.reserve('today-try', 0.01, DAY, CONFIG, 'generate')).toEqual({
      ok: false,
      reason: 'storage_error',
    });
    expect(ledger.reserve('tomorrow-try', 0.01, tomorrow, CONFIG, 'generate')).toEqual({
      ok: false,
      reason: 'storage_error',
    });
    expect(ledger.summary(DAY, CONFIG).hardCapReached).toBe(true);
    expect(kvHas('ledger')).toBe(true);
  });

  it('without a legacy key, reserve and summary behave normally', () => {
    const { ledger } = createDeviceSpendLedgerHarness();
    expect(ledger.reserve('ok', 0.01, DAY, CONFIG, 'generate')).toEqual({ ok: true });
    expect(ledger.summary(DAY, CONFIG).hardCapReached).toBe(false);
  });
});

const PAST_DAY = '2026-08-01';

function buildTamperedPastDayBucketWith2000Attempts(dayKey: string) {
  const createdMs = Date.parse(`${dayKey}T00:00:00.000Z`);
  const a: Record<string, { u: number; t: string; S: 1; a: number; c: number }> = Object.create(null);
  for (let i = 0; i < 2000; i += 1) {
    const id = `a${String(i).padStart(4, '0')}`;
    a[id] = { u: 1, t: 'generate', S: 1, a: 1, c: createdMs };
  }
  return { s: 2000, r: 0, o: 0, a, k: { generate: 2000 } };
}

describe('ledger limit fence on decode (Q1)', () => {
  beforeEach(() => {
    vi.useFakeTimers({ now: NOW });
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it('fences a past day with 2000 attempts: that day fail-closed, today still works', () => {
    const pastBucket = buildTamperedPastDayBucketWith2000Attempts(PAST_DAY);
    expect(
      storedDayBucketViolatesLedgerLimits(
        validateStoredDayBucket(pastBucket)!,
        new TextEncoder().encode(JSON.stringify(pastBucket)).length
      )
    ).toBe(true);
    const { ledger } = createDeviceSpendLedgerHarness(undefined, {
      initialKv: { [bucketStorageKey(PAST_DAY)]: pastBucket },
    });
    const pastSummary = ledger.summary(PAST_DAY, CONFIG);
    expect(pastSummary.hardCapReached).toBe(true);
    expect(pastSummary.attemptLimitReached).toBe(true);
    expect(ledger.reserve('today-1', 0.01, DAY, CONFIG, 'generate')).toEqual({ ok: true });
    expect(ledger.summary(DAY, CONFIG).hardCapReached).toBe(false);
  });
});

describe('corrupt day reconcile (Q2)', () => {
  it('returns storage_error like reserve', () => {
    const state = emptyLedgerState();
    markDayStorageCorrupt(state, DAY);
    expect(reconcileAttempt(state, DAY, 'x', 0.01)).toEqual({ ok: false, reason: 'storage_error' });
  });
});

describe('Sol round-4 decode regressions', () => {
  beforeEach(() => {
    vi.useFakeTimers({ now: NOW });
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  const HIGH_CONFIG = { dailyCapUSD: 10_000, softThresholdUSD: 5000 };

  it('reload after reconcile task override keeps day valid (entry.task matches k)', () => {
    const originalTask = 'task-original-xx';
    const overrideTask = 'task-override-xx';
    const { ledger, getStoredState } = createDeviceSpendLedgerHarness();
    expect(ledger.reserve('override-id', 0.01, DAY, CONFIG, originalTask)).toEqual({ ok: true });
    expect(ledger.reconcile(DAY, 'override-id', 0.01, overrideTask)).toEqual({ ok: true });
    const reloaded = getStoredState();
    expect(isDayStorageCorrupt(reloaded!, DAY)).toBe(false);
    expect(reloaded?.days[DAY]?.attempts['override-id']?.task).toBe(overrideTask);
    expect(reloaded?.days[DAY]?.tasks[overrideTask]).toBeGreaterThan(0);
  });

  it('reload after actual-over-ceiling at max reserve bound keeps day valid (O matches recompute)', () => {
    const { ledger, getStoredState } = createDeviceSpendLedgerHarness();
    expect(ledger.reserve('ceil-id', MAX_ATTEMPT_USD, DAY, HIGH_CONFIG, 'generate')).toEqual({
      ok: true,
    });
    expect(ledger.reconcile(DAY, 'ceil-id', MAX_ATTEMPT_USD + 500)).toEqual({
      ok: false,
      reason: 'actual_over_ceiling',
    });
    const reloaded = getStoredState();
    expect(isDayStorageCorrupt(reloaded!, DAY)).toBe(false);
    expect(reloaded?.days[DAY]?.overReservationCount).toBe(1);
    expect(reloaded?.days[DAY]?.attempts['ceil-id']?.overReservation).toBe(true);
  });

  it('throws while probing raw bucket JSON mark only that day corrupt', () => {
    const cyclic: Record<string, unknown> = { s: 0, r: 0, o: 0, a: {}, k: {} };
    cyclic.self = cyclic;
    const kv = memoryKv({
      [bucketStorageKey(PAST_DAY)]: cyclic,
      [bucketStorageKey(DAY)]: { s: 0, r: 0, o: 0, a: {}, k: {} },
    });
    const state = loadLedgerFromStorage(kv);
    expect(isDayStorageCorrupt(state, PAST_DAY)).toBe(true);
    expect(isDayStorageCorrupt(state, DAY)).toBe(false);
    expect(state.days[DAY]).toBeDefined();
  });
});

function maxLengthTaskUnique(index: number): string {
  const suffix = String(index).padStart(4, '0');
  return `${'T'.repeat(16 - suffix.length)}${suffix}`;
}

/** Exceeds {@link MAX_BUCKET_BYTES} when encoded (for persist-guard tests only). */
function buildPersistOversizedDay(dayKey: string) {
  const micro = MAX_ATTEMPT_USD * MICRO_USD;
  const iso = `${dayKey}T23:59:59.999Z`;
  const attempts = Object.create(null);
  const tasks = Object.create(null);
  let i = 0;
  let day: DayRecord;
  do {
    const attemptId = worstCaseAttemptId(i);
    const task = maxLengthTaskUnique(i);
    attempts[attemptId] = {
      attemptId,
      upperBoundMicro: micro - 1,
      actualMicro: micro,
      task,
      state: 'reconciled',
      createdAt: iso,
      reconciledAt: iso,
      overReservation: true,
    };
    tasks[task] = (tasks[task] ?? 0) + micro;
    day = {
      date: dayKey,
      spentMicro: micro * (i + 1),
      reservedMicro: 0,
      overReservationCount: i + 1,
      attempts,
      tasks,
    };
    i += 1;
  } while (storedDayBucketJsonByteLength(day) <= MAX_BUCKET_BYTES && i < 650);
  expect(storedDayBucketJsonByteLength(day)).toBeGreaterThan(MAX_BUCKET_BYTES);
  return day;
}

describe('persistLedgerToStorage bucket size guard', () => {
  it('refuses persist without writing when an encoded day exceeds MAX_BUCKET_BYTES', () => {
    const kv = memoryKv();
    const state = emptyLedgerState();
    state.days[DAY] = buildPersistOversizedDay(DAY);
    expect(persistLedgerToStorage(kv, state, new Set())).toEqual({
      ok: false,
      reason: 'bucket_too_large',
    });
    expect([...kv.list({ prefix: 'bucket:' })]).toHaveLength(0);
  });
});

describe('DeviceSpendLedger persist guard', () => {
  beforeEach(() => {
    vi.useFakeTimers({ now: NOW });
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it('returns storage_error on persist when an encoded day exceeds MAX_BUCKET_BYTES', () => {
    const initial = emptyLedgerState();
    initial.days[DAY] = buildPersistOversizedDay(DAY);
    const { ledger } = createDeviceSpendLedgerHarness(initial, {
      maxValueBytes: MAX_BUCKET_BYTES * 2,
    });
    expect(
      ledger.reconcile(DAY, worstCaseAttemptId(0), MAX_ATTEMPT_USD, maxLengthTaskUnique(0))
    ).toEqual({
      ok: false,
      reason: 'storage_error',
    });
  });
});

describe('MAX_ATTEMPT_USD bounds', () => {
  it('rejects reserve above the per-attempt ceiling', () => {
    const state = emptyLedgerState();
    expect(reserveAttempt(state, 'big', MAX_ATTEMPT_USD + 0.01, DAY, CONFIG, 'generate', NOW)).toEqual({
      ok: false,
      reason: 'invalid',
    });
    expect(reserveAttempt(state, 'ok', MAX_ATTEMPT_USD, DAY, CONFIG, 'generate', NOW)).toEqual({
      ok: true,
    });
  });
});

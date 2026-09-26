/**
 * Per-day bucket JSON size and steady-state storage through DeviceSpendLedger.
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import {
  MAX_ATTEMPTS_PER_DAY,
  MAX_ATTEMPT_ID_LENGTH,
  MAX_TASK_NAME_LENGTH,
  MAX_ATTEMPT_USD,
  MAX_DISTINCT_TASKS_PER_DAY,
  MAX_BUCKET_BYTES,
  MICRO_USD,
  emptyLedgerState,
  hydrateDayRecord,
  reconcileAttempt,
  reserveAttempt,
  type DayRecord,
} from '../src/ledgerCore.js';
import { storedDayBucketJsonByteLength } from '../src/ledgerBucketStorage.js';
import { createDeviceSpendLedgerHarness } from './helpers.js';

const DAY = '2026-09-26';
const CONFIG = { dailyCapUSD: 1_000_000, softThresholdUSD: 500_000 };
const FROZEN_NOW = new Date(`${DAY}T12:00:00.000Z`);

/** Measured in test run; exported for reporting. */
export let trueWorstCaseBucketBytes = 0;

function utcDayKeyMinusDays(day: string, daysBack: number): string {
  const ms = Date.parse(`${day}T00:00:00.000Z`) - daysBack * 86_400_000;
  return new Date(ms).toISOString().split('T')[0];
}

export function worstCaseAttemptId(index: number): string {
  const suffix = String(index).padStart(4, '0');
  return `${'A'.repeat(MAX_ATTEMPT_ID_LENGTH - suffix.length)}${suffix}`;
}

function maxLengthTask(index: number): string {
  const suffix = String(index).padStart(2, '0');
  return `${'T'.repeat(MAX_TASK_NAME_LENGTH - suffix.length)}${suffix}`;
}

/** True worst-case: 500 max-length ids, 32 max-length tasks, max bounded USD per field. */
export function buildTrueWorstCaseSettledDay(dayKey: string): DayRecord {
  const attempts = Object.create(null) as DayRecord['attempts'];
  const tasks = Object.create(null) as DayRecord['tasks'];
  const micro = MAX_ATTEMPT_USD * MICRO_USD;
  const epochMs = Date.parse(`${dayKey}T23:59:59.999Z`);
  const iso = new Date(epochMs).toISOString();
  for (let i = 0; i < MAX_ATTEMPTS_PER_DAY; i += 1) {
    const attemptId = worstCaseAttemptId(i);
    const task = maxLengthTask(i % MAX_DISTINCT_TASKS_PER_DAY);
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
  }
  return {
    date: dayKey,
    spentMicro: micro * MAX_ATTEMPTS_PER_DAY,
    reservedMicro: 0,
    overReservationCount: MAX_ATTEMPTS_PER_DAY,
    attempts,
    tasks,
  };
}

describe('ledger bucket byte budget', () => {
  it('true worst-case single day JSON stays under MAX_BUCKET_BYTES', () => {
    const day = buildTrueWorstCaseSettledDay(DAY);
    expect(Object.keys(day.attempts).length).toBe(MAX_ATTEMPTS_PER_DAY);
    expect(Object.keys(day.tasks).length).toBe(MAX_DISTINCT_TASKS_PER_DAY);
    const bytes = storedDayBucketJsonByteLength(day);
    trueWorstCaseBucketBytes = bytes;
    expect(bytes).toBeLessThan(MAX_BUCKET_BYTES);
  });
});

describe('DeviceSpendLedger steady-state storage', () => {
  beforeEach(() => {
    vi.useFakeTimers({ now: FROZEN_NOW });
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it('31 worst-case settled days plus today and tomorrow: reserve, reconcile, summary without storage errors', () => {
    const initial = emptyLedgerState();
    for (let age = 1; age <= 31; age += 1) {
      const dayKey = utcDayKeyMinusDays(DAY, age);
      initial.days[dayKey] = buildTrueWorstCaseSettledDay(dayKey);
    }
    const tomorrow = utcDayKeyMinusDays(DAY, -1);
    initial.days[tomorrow] = buildTrueWorstCaseSettledDay(tomorrow);
    initial.days[DAY] = {
      date: DAY,
      spentMicro: 0,
      reservedMicro: 50_000,
      overReservationCount: 0,
      attempts: {
        'open-today-hold': {
          attemptId: 'open-today-hold',
          upperBoundMicro: 50_000,
          task: 'generate',
          state: 'reserved',
          createdAt: `${DAY}T01:00:00.000Z`,
        },
      },
      tasks: Object.create(null),
    };

    const { ledger } = createDeviceSpendLedgerHarness(initial, { maxValueBytes: MAX_BUCKET_BYTES });
    expect(ledger.reconcile(DAY, 'open-today-hold', 0.02, 'generate')).toEqual({ ok: true });
    expect(ledger.reserve('steady-new', 0.03, DAY, CONFIG, 'generate')).toEqual({ ok: true });
    const todaySummary = ledger.summary(DAY, CONFIG);
    expect(todaySummary.hardCapReached).toBe(false);
    expect(todaySummary.attemptLimitReached).toBe(false);
    expect(ledger.summary(tomorrow, CONFIG).attemptLimitReached).toBe(true);
    expect(ledger.reserve('extra-tomorrow', 0.01, tomorrow, CONFIG, maxLengthTask(0))).toEqual({
      ok: false,
      reason: 'attempt_limit',
    });
  });
});

describe('prototype-key attempt ids after storage reload', () => {
  beforeEach(() => {
    vi.useFakeTimers({ now: FROZEN_NOW });
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  const POLLUTION_IDS = ['hasOwnProperty', 'constructor', 'valueOf', 'isPrototypeOf', '__proto__'] as const;

  for (const attemptId of POLLUTION_IDS) {
    it(`reserve and reconcile "${attemptId}" after JSON reload`, () => {
      const state = emptyLedgerState();
      expect(reserveAttempt(state, attemptId, 0.1, DAY, CONFIG, 'generate', FROZEN_NOW)).toEqual({
        ok: true,
      });
      const raw = JSON.parse(JSON.stringify(state.days[DAY])) as DayRecord;
      const reloaded = emptyLedgerState();
      reloaded.days[DAY] = hydrateDayRecord(raw);
      expect(reconcileAttempt(reloaded, DAY, attemptId, 0.05, 'generate')).toEqual({ ok: true });
    });
  }
});

describe('MAX_DISTINCT_TASKS_PER_DAY', () => {
  beforeEach(() => {
    vi.useFakeTimers({ now: FROZEN_NOW });
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it('rejects a 33rd distinct task on the same UTC day', () => {
    const state = emptyLedgerState();
    for (let i = 0; i < MAX_DISTINCT_TASKS_PER_DAY; i += 1) {
      expect(
        reserveAttempt(state, `t${i}`, 0.01, DAY, CONFIG, maxLengthTask(i), FROZEN_NOW)
      ).toEqual({ ok: true });
    }
    expect(reserveAttempt(state, 'extra-task', 0.01, DAY, CONFIG, 'new-task-name-xx', FROZEN_NOW)).toEqual({
      ok: false,
      reason: 'task_limit',
    });
  });

  it('rejects reconcile task override that would add a 33rd distinct task', () => {
    const state = emptyLedgerState();
    for (let i = 0; i < MAX_DISTINCT_TASKS_PER_DAY; i += 1) {
      expect(
        reserveAttempt(state, `a${i}`, 0.01, DAY, CONFIG, maxLengthTask(i), FROZEN_NOW)
      ).toEqual({ ok: true });
    }
    expect(
      reserveAttempt(state, 'dup-hold', 0.01, DAY, CONFIG, maxLengthTask(0), FROZEN_NOW)
    ).toEqual({ ok: true });
    const snapshot = JSON.stringify(state.days[DAY]);
    expect(
      reconcileAttempt(state, DAY, 'dup-hold', 0.005, 'new-33rd-task-xx')
    ).toEqual({ ok: false, reason: 'task_limit' });
    expect(JSON.stringify(state.days[DAY])).toBe(snapshot);
  });

  it('true worst-case settled day cannot exceed task cap via reconcile override', () => {
    const state = emptyLedgerState();
    const day = buildTrueWorstCaseSettledDay(DAY);
    const probeId = 'override-probe';
    day.attempts[probeId] = {
      attemptId: probeId,
      upperBoundMicro: MICRO_USD,
      task: maxLengthTask(0),
      state: 'reserved',
      createdAt: `${DAY}T01:00:00.000Z`,
    };
    day.reservedMicro += MICRO_USD;
    state.days[DAY] = day;
    expect(reconcileAttempt(state, DAY, probeId, 0.01, 'zzzzzzzzzzzzzzzz')).toEqual({
      ok: false,
      reason: 'task_limit',
    });
  });
});

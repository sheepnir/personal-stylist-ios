/**
 * Per-day bucket JSON size and steady-state storage through DeviceSpendLedger.
 */

import { describe, it, expect } from 'vitest';
import {
  MAX_ATTEMPTS_PER_DAY,
  MAX_ATTEMPT_ID_LENGTH,
  MAX_TASK_NAME_LENGTH,
  MAX_BUCKET_BYTES,
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

function utcDayKeyMinusDays(day: string, daysBack: number): string {
  const ms = Date.parse(`${day}T00:00:00.000Z`) - daysBack * 86_400_000;
  return new Date(ms).toISOString().split('T')[0];
}

export function worstCaseAttemptId(index: number): string {
  const suffix = String(index).padStart(4, '0');
  return `${'A'.repeat(MAX_ATTEMPT_ID_LENGTH - suffix.length)}${suffix}`;
}

export function buildWorstCaseSettledDay(dayKey: string): DayRecord {
  const attempts = Object.create(null) as DayRecord['attempts'];
  const tasks = Object.create(null) as DayRecord['tasks'];
  const task = 't'.repeat(MAX_TASK_NAME_LENGTH);
  const iso = `${dayKey}T23:59:59.999Z`;
  let spentMicro = 0;
  for (let i = 0; i < MAX_ATTEMPTS_PER_DAY; i += 1) {
    const attemptId = worstCaseAttemptId(i);
    const micro = 900_000;
    attempts[attemptId] = {
      attemptId,
      upperBoundMicro: micro,
      actualMicro: micro,
      task,
      state: 'reconciled',
      createdAt: iso,
      reconciledAt: iso,
      overReservation: true,
    };
    spentMicro += micro;
  }
  tasks[task] = spentMicro;
  return {
    date: dayKey,
    spentMicro,
    reservedMicro: 0,
    overReservationCount: MAX_ATTEMPTS_PER_DAY,
    attempts,
    tasks,
  };
}

describe('ledger bucket byte budget', () => {
  it('worst-case single day JSON stays under MAX_BUCKET_BYTES', () => {
    const day = buildWorstCaseSettledDay(DAY);
    expect(Object.keys(day.attempts).length).toBe(MAX_ATTEMPTS_PER_DAY);
    const bytes = storedDayBucketJsonByteLength(day);
    expect(bytes).toBeLessThan(MAX_BUCKET_BYTES);
  });
});

describe('DeviceSpendLedger steady-state storage', () => {
  it('31 worst-case settled days plus today and tomorrow: reserve, reconcile, summary without storage errors', () => {
    const initial = emptyLedgerState();
    for (let age = 1; age <= 31; age += 1) {
      const dayKey = utcDayKeyMinusDays(DAY, age);
      initial.days[dayKey] = buildWorstCaseSettledDay(dayKey);
    }
    const tomorrow = utcDayKeyMinusDays(DAY, -1);
    initial.days[tomorrow] = buildWorstCaseSettledDay(tomorrow);
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

    const { ledger } = createDeviceSpendLedgerHarness(initial);
    expect(ledger.reconcile(DAY, 'open-today-hold', 0.02, 'generate')).toEqual({ ok: true });
    expect(ledger.reserve('steady-new', 0.03, DAY, CONFIG, 'generate')).toEqual({ ok: true });
    const todaySummary = ledger.summary(DAY, CONFIG);
    expect(todaySummary.hardCapReached).toBe(false);
    expect(todaySummary.attemptLimitReached).toBe(false);
    expect(ledger.summary(tomorrow, CONFIG).attemptLimitReached).toBe(true);
    expect(ledger.reserve('extra-tomorrow', 0.01, tomorrow, CONFIG, 'generate')).toEqual({
      ok: false,
      reason: 'attempt_limit',
    });
  });
});

describe('prototype-key attempt ids after storage reload', () => {
  const POLLUTION_IDS = ['hasOwnProperty', 'constructor', 'valueOf', 'isPrototypeOf', '__proto__'] as const;

  for (const attemptId of POLLUTION_IDS) {
    it(`reserve and reconcile "${attemptId}" after JSON reload`, () => {
      const state = emptyLedgerState();
      expect(reserveAttempt(state, attemptId, 0.1, DAY, CONFIG, 'generate')).toEqual({ ok: true });
      const raw = JSON.parse(JSON.stringify(state.days[DAY])) as DayRecord;
      const reloaded = emptyLedgerState();
      reloaded.days[DAY] = hydrateDayRecord(raw);
      expect(reconcileAttempt(reloaded, DAY, attemptId, 0.05, 'generate')).toEqual({ ok: true });
    });
  }
});

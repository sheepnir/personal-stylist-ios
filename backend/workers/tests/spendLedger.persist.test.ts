import { describe, it, expect } from 'vitest';
import { shouldPersistInMemoryLedger } from '../src/spendLedger.js';
import {
  emptyLedgerState,
  pruneOldDays,
  removeEmptyDayBucket,
  reserveAttempt,
} from '../src/ledgerCore.js';

const DAY = '2026-09-26';
const CONFIG = { dailyCapUSD: 1.0, softThresholdUSD: 0.5 };

describe('DeviceSpendLedger persistence policy', () => {
  it('does not persist when reserve fails without pruning or mutation', () => {
    const state = emptyLedgerState();
    const keysBefore = Object.keys(state.days).sort().join('\0');
    const pruned = pruneOldDays(state, new Date(`${DAY}T12:00:00.000Z`));
    const result = reserveAttempt(state, 'a1', 999, DAY, CONFIG);
    if (!result.ok) {
      removeEmptyDayBucket(state, DAY);
    }
    const keysAfter = Object.keys(state.days).sort().join('\0');
    expect(result.ok).toBe(false);
    expect(shouldPersistInMemoryLedger(result.ok, pruned, keysBefore, keysAfter)).toBe(false);
    expect(state.days[DAY]).toBeUndefined();
  });

  it('persists when pruning removed stale buckets', () => {
    const state = emptyLedgerState();
    state.days['1999-01-01'] = {
      date: '1999-01-01',
      spentMicro: 1,
      reservedMicro: 0,
      overReservationCount: 0,
      attempts: Object.create(null),
      tasks: Object.create(null),
    };
    const keysBefore = Object.keys(state.days).sort().join('\0');
    const pruned = pruneOldDays(state, new Date(`${DAY}T12:00:00.000Z`));
    const keysAfter = Object.keys(state.days).sort().join('\0');
    expect(shouldPersistInMemoryLedger(false, pruned, keysBefore, keysAfter)).toBe(true);
  });
});

import { describe, it, expect } from 'vitest';
import { DeviceSpendLedger, shouldPersistInMemoryLedger } from '../src/spendLedger.js';
import { configToMicro } from '../src/ledgerCore.js';

describe('DeviceSpendLedger config defense in depth', () => {
  it('configToMicro rejects unsafe caps', () => {
    expect(configToMicro({ dailyCapUSD: Number.NaN, softThresholdUSD: 0.5 })).toEqual({
      ok: false,
      configError: true,
    });
    expect(configToMicro({ dailyCapUSD: Number.POSITIVE_INFINITY, softThresholdUSD: 0.5 })).toEqual({
      ok: false,
      configError: true,
    });
  });

  it('shouldPersistInMemoryLedger stays false on config_error reserve without prune', () => {
    expect(shouldPersistInMemoryLedger(false, false, '', '')).toBe(false);
  });
});

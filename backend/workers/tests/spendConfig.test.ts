/**
 * resolveSpendConfig strict parsing (#13-a).
 */

import { describe, it, expect, vi, beforeEach } from 'vitest';
import { resolveSpendConfig, SPEND_CONFIG, resetSpendConfigLogStateForTests } from '../src/types.js';
import { reserveSpend, isHardCapReached } from '../src/usage.js';
import { generateDeviceToken } from '../src/tokens.js';
import { createSpendLedgerMock, emptyLedger } from './helpers.js';
import type { Env } from '../src/types.js';

describe('resolveSpendConfig', () => {
  beforeEach(() => {
    vi.restoreAllMocks();
    resetSpendConfigLogStateForTests();
  });

  it('uses sample defaults when env vars are unset', () => {
    expect(resolveSpendConfig({})).toEqual({
      configError: false,
      dailyCapUSD: SPEND_CONFIG.dailyCapUSD,
      softThresholdUSD: SPEND_CONFIG.softThresholdUSD,
    });
  });

  it.each(['abc', '1,00', '$1', '-1', '0', 'NaN', '1e400', '0x10'])(
    'treats invalid DAILY_CAP_USD=%s as config error without falling back to 1.00',
    (raw) => {
      const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
      const resolved = resolveSpendConfig({ DAILY_CAP_USD: raw });
      expect(resolved).toEqual({ configError: true });
      expect(warn).toHaveBeenCalledWith(
        'Spend configuration invalid; ledger reservations disabled.'
      );
    }
  );

  it('accepts plain decimal strings', () => {
    expect(resolveSpendConfig({ DAILY_CAP_USD: '4', SOFT_THRESHOLD_USD: '3' })).toEqual({
      configError: false,
      dailyCapUSD: 4,
      softThresholdUSD: 3,
    });
  });
});

describe('invalid deployment config fail-closed in usage', () => {
  it('refuses reserve and reports cap reached', async () => {
    const mock = createSpendLedgerMock();
    const env: Env = {
      OPENROUTER_API_KEY: 'k',
      USAGE_LEDGER: emptyLedger(),
      SPEND_LEDGER: mock.namespace as Env['SPEND_LEDGER'],
      DAILY_CAP_USD: 'abc',
    };
    const token = generateDeviceToken();
    expect(await reserveSpend(token, 'a1', 0.1, env)).toEqual({ ok: false, reason: 'config_error' });
    expect(await isHardCapReached(token, env)).toBe(true);
  });
});

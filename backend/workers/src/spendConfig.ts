/**
 * Deploy-time spend cap resolution (env vars → ledger config).
 */

import { capUsdToMicro, MAX_DEPLOYABLE_CAP_USD } from './ledgerCore.js';
import type { Env } from './types.js';
import { SPEND_CONFIG, type SpendConfig } from './types.js';

export type ResolvedSpendConfig =
  | { configError: false; dailyCapUSD: number; softThresholdUSD: number }
  | { configError: true };

const PLAIN_DECIMAL_USD = /^\d+(\.\d+)?$/;

function parsePlainDecimalUsd(raw: string | undefined): number | null | 'unset' {
  if (raw === undefined || raw.trim() === '') {
    return 'unset';
  }
  const trimmed = raw.trim();
  if (!PLAIN_DECIMAL_USD.test(trimmed)) {
    return null;
  }
  const n = Number(trimmed);
  if (!Number.isFinite(n) || n <= 0) {
    return null;
  }
  return n;
}

function isDeployableCapUsd(usd: number): boolean {
  if (!Number.isFinite(usd) || usd <= 0 || usd > MAX_DEPLOYABLE_CAP_USD) {
    return false;
  }
  return capUsdToMicro(usd).ok;
}

let loggedConfigError = false;

export function resetSpendConfigLogStateForTests(): void {
  loggedConfigError = false;
}

function logSpendConfigError(): void {
  if (loggedConfigError) return;
  loggedConfigError = true;
  console.warn('Spend configuration invalid; ledger reservations disabled.');
}

/**
 * Resolve spend caps from env. Unset vars use sample defaults; an explicitly invalid
 * value or one that does not convert to safe positive micro-USD is a config error.
 */
export function resolveSpendConfig(
  env: Pick<Env, 'DAILY_CAP_USD' | 'SOFT_THRESHOLD_USD'>
): ResolvedSpendConfig {
  const capParsed = parsePlainDecimalUsd(env.DAILY_CAP_USD);
  if (capParsed === null) {
    logSpendConfigError();
    return { configError: true };
  }
  const dailyCapUSD = capParsed === 'unset' ? SPEND_CONFIG.dailyCapUSD : capParsed;
  if (!isDeployableCapUsd(dailyCapUSD)) {
    logSpendConfigError();
    return { configError: true };
  }

  const softParsed = parsePlainDecimalUsd(env.SOFT_THRESHOLD_USD);
  if (softParsed === null) {
    logSpendConfigError();
    return { configError: true };
  }
  const softUsd = softParsed === 'unset' ? SPEND_CONFIG.softThresholdUSD : softParsed;
  if (!isDeployableCapUsd(softUsd)) {
    logSpendConfigError();
    return { configError: true };
  }

  const softThresholdUSD = Math.min(softUsd, dailyCapUSD);
  return { configError: false, dailyCapUSD, softThresholdUSD };
}

/** SpendConfig for ledger calls; invalid deployment config yields NaN caps (fail closed in core). */
export function spendConfigFromEnv(
  env: Pick<Env, 'DAILY_CAP_USD' | 'SOFT_THRESHOLD_USD'>
): SpendConfig {
  const resolved = resolveSpendConfig(env);
  if (resolved.configError) {
    return { dailyCapUSD: Number.NaN, softThresholdUSD: Number.NaN };
  }
  return {
    dailyCapUSD: resolved.dailyCapUSD,
    softThresholdUSD: resolved.softThresholdUSD,
  };
}

/**
 * Usage tracking and spend cap enforcement (M0-09 minimal KV-based ledger).
 * Hard cap and soft threshold come from `resolveSpendConfig(env)` (sample defaults, env-overridable).
 */

import type { Env, SpendRecord } from './types.js';
import { resolveSpendConfig } from './types.js';
import { hashToken } from './tokens.js';

export { hashToken };

const KV_TTL_DAYS = 30;

/**
 * Get today's spend record for a device token.
 */
export async function getSpendRecord(
  deviceToken: string,
  env: Env
): Promise<SpendRecord> {
  const today = getTodayDateString();
  const tokenHash = await hashToken(deviceToken);
  const key = spendKey(tokenHash, today);

  const stored = await env.USAGE_LEDGER.get(key, 'json');

  if (stored) {
    return stored as SpendRecord;
  }

  // Initialize new record
  return {
    tokenHash,
    date: today,
    spentUSD: 0,
    reservedUSD: 0,
    tasks: {},
    lastUpdated: new Date().toISOString(),
  };
}

/**
 * Update spend record after a task completes.
 */
export async function recordSpend(
  deviceToken: string,
  task: string,
  costUSD: number,
  env: Env
): Promise<void> {
  const today = getTodayDateString();
  const record = await getSpendRecord(deviceToken, env);
  const key = spendKey(record.tokenHash, today);

  record.spentUSD += costUSD;
  record.tasks[task] = (record.tasks[task] || 0) + costUSD;
  record.lastUpdated = new Date().toISOString();
  
  // Store with 30-day TTL
  await env.USAGE_LEDGER.put(
    key,
    JSON.stringify(record),
    { expirationTtl: 60 * 60 * 24 * KV_TTL_DAYS }
  );
}

/**
 * Check if hard cap is reached (triggers deterministic fallback).
 */
export async function isHardCapReached(
  deviceToken: string,
  env: Env
): Promise<boolean> {
  const record = await getSpendRecord(deviceToken, env);
  const totalSpent = record.spentUSD + record.reservedUSD;
  return totalSpent >= resolveSpendConfig(env).dailyCapUSD;
}

/**
 * Check if soft threshold is reached (triggers secondary model).
 */
export async function isSoftThresholdReached(
  deviceToken: string,
  env: Env
): Promise<boolean> {
  const record = await getSpendRecord(deviceToken, env);
  const totalSpent = record.spentUSD + record.reservedUSD;
  return totalSpent >= resolveSpendConfig(env).softThresholdUSD;
}

/**
 * Get usage summary for last 7 and 30 days (M0-09 stub: returns today's data).
 */
export async function getUsageSummary(
  deviceToken: string,
  env: Env
): Promise<{
  last7DaysUSD: number;
  last30DaysUSD: number;
  dailyCapUSD: number;
  softThresholdUSD: number;
  spentTodayUSD: number;
  reservedTodayUSD: number;
  softThresholdReached: boolean;
  hardCapReached: boolean;
  ledgerDayEndsAt: string | null;
  byTask: Record<string, number>;
}> {
  const record = await getSpendRecord(deviceToken, env);
  
  // M0-09 minimal: only today's data; full 7/30-day aggregation in M0-18
  const totalSpent = record.spentUSD + record.reservedUSD;
  
  return {
    last7DaysUSD: record.spentUSD, // Stub: same as today
    last30DaysUSD: record.spentUSD, // Stub: same as today
    dailyCapUSD: resolveSpendConfig(env).dailyCapUSD,
    softThresholdUSD: resolveSpendConfig(env).softThresholdUSD,
    spentTodayUSD: record.spentUSD,
    reservedTodayUSD: record.reservedUSD,
    softThresholdReached: totalSpent >= resolveSpendConfig(env).softThresholdUSD,
    hardCapReached: totalSpent >= resolveSpendConfig(env).dailyCapUSD,
    ledgerDayEndsAt: getEndOfDayISO(),
    byTask: record.tasks,
  };
}

/**
 * Get today's date as YYYY-MM-DD string.
 */
function getTodayDateString(): string {
  return new Date().toISOString().split('T')[0];
}

/**
 * Get end of today as ISO timestamp.
 */
function getEndOfDayISO(): string {
  const now = new Date();
  const endOfDay = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 59, 999);
  return endOfDay.toISOString();
}

/**
 * Generate KV key for spend record from a token hash.
 */
function spendKey(tokenHash: string, date: string): string {
  return `spend:${tokenHash}:${date}`;
}

/**
 * Usage tracking and spend cap enforcement via per-device Durable Object ledger (#13-a).
 * Hard cap and soft threshold come from `resolveSpendConfig(env)` (sample defaults, env-overridable).
 */

import type { Env, SpendRecord } from './types.js';
import { resolveSpendConfig } from './types.js';
import { hashToken, deviceLocatorFromToken } from './tokens.js';

export { hashToken };

function spendConfig(env: Env) {
  return resolveSpendConfig(env);
}

function ledgerStub(deviceLocator: string, env: Env) {
  if (!env.SPEND_LEDGER) throw new Error('Spend ledger unavailable');
  return env.SPEND_LEDGER.getByName(deviceLocator);
}

/**
 * Legacy shared tokens and missing bindings have no ledger.
 */
function locatorForLedger(deviceToken: string, env: Env): string | null {
  const locator = deviceLocatorFromToken(deviceToken);
  if (!locator || !env.SPEND_LEDGER) return null;
  return locator;
}

/**
 * Get today's spend record for a device token (legacy tokens → empty in-memory shape).
 */
export async function getSpendRecord(
  deviceToken: string,
  env: Env
): Promise<SpendRecord> {
  const today = getTodayDateString();
  const tokenHash = await hashToken(deviceToken);
  const locator = locatorForLedger(deviceToken, env);

  if (!locator) {
    return {
      tokenHash,
      date: today,
      spentUSD: 0,
      reservedUSD: 0,
      unresolvedAttempts: 0,
      tasks: {},
      lastUpdated: new Date().toISOString(),
    };
  }

  const summary = await ledgerStub(locator, env).summary(today, spendConfig(env));
  return {
    tokenHash,
    date: today,
    spentUSD: summary.spentUSD,
    reservedUSD: summary.reservedUSD,
    unresolvedAttempts: summary.unresolvedAttempts,
    tasks: summary.byTask,
    lastUpdated: new Date().toISOString(),
  };
}

/**
 * Reserve an upper bound for a paid attempt (no-op for legacy shared tokens).
 */
export async function reserveSpend(
  deviceToken: string,
  attemptId: string,
  upperBoundUSD: number,
  env: Env,
  day: string = getTodayDateString()
): Promise<{ ok: boolean; reason?: string }> {
  const locator = locatorForLedger(deviceToken, env);
  if (!locator) return { ok: false, reason: 'no_ledger' };
  return ledgerStub(locator, env).reserve(attemptId, upperBoundUSD, day, spendConfig(env));
}

/**
 * Reconcile a reservation to the actual provider cost.
 */
export async function reconcileSpend(
  deviceToken: string,
  attemptId: string,
  actualUSD: number,
  env: Env
): Promise<{ ok: boolean; reason?: string }> {
  const locator = locatorForLedger(deviceToken, env);
  if (!locator) return { ok: false, reason: 'no_ledger' };
  return ledgerStub(locator, env).reconcile(attemptId, actualUSD);
}

/**
 * Mark a paid attempt's outcome unknown; reservation stays in place (#13-b).
 */
export async function markUnknownSpend(
  deviceToken: string,
  attemptId: string,
  env: Env,
  generationId?: string
): Promise<{ ok: boolean; reason?: string }> {
  const locator = locatorForLedger(deviceToken, env);
  if (!locator) return { ok: false, reason: 'no_ledger' };
  return ledgerStub(locator, env).markUnknown(attemptId, generationId);
}

/**
 * @deprecated KV path removed; use {@link reserveSpend} + {@link reconcileSpend}. Kept for tests migrating off KV.
 */
export async function recordSpend(
  deviceToken: string,
  task: string,
  costUSD: number,
  env: Env
): Promise<void> {
  const attemptId = `test-record:${task}:${costUSD}`;
  const reserved = await reserveSpend(deviceToken, attemptId, costUSD, env);
  if (!reserved.ok) return;
  await reconcileSpend(deviceToken, attemptId, costUSD, env);
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
  return totalSpent >= spendConfig(env).dailyCapUSD;
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
  return totalSpent >= spendConfig(env).softThresholdUSD;
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
  unresolvedAttempts: number;
  softThresholdReached: boolean;
  hardCapReached: boolean;
  ledgerDayEndsAt: string | null;
  byTask: Record<string, number>;
}> {
  const record = await getSpendRecord(deviceToken, env);
  const config = spendConfig(env);
  const totalSpent = record.spentUSD + record.reservedUSD;

  return {
    last7DaysUSD: record.spentUSD,
    last30DaysUSD: record.spentUSD,
    dailyCapUSD: config.dailyCapUSD,
    softThresholdUSD: config.softThresholdUSD,
    spentTodayUSD: record.spentUSD,
    reservedTodayUSD: record.reservedUSD,
    unresolvedAttempts: record.unresolvedAttempts,
    softThresholdReached: totalSpent >= config.softThresholdUSD,
    hardCapReached: totalSpent >= config.dailyCapUSD,
    ledgerDayEndsAt: getEndOfDayISO(),
    byTask: record.tasks,
  };
}

function getTodayDateString(): string {
  return new Date().toISOString().split('T')[0];
}

function getEndOfDayISO(): string {
  const now = new Date();
  const endOfDay = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 59, 999);
  return endOfDay.toISOString();
}

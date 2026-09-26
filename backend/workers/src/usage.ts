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

function isLegacySharedToken(deviceToken: string): boolean {
  return deviceLocatorFromToken(deviceToken) === null;
}

function deviceLocator(deviceToken: string): string {
  const locator = deviceLocatorFromToken(deviceToken);
  if (!locator) throw new Error('expected per-device token');
  return locator;
}

type LedgerAccess =
  | { kind: 'legacy' }
  | { kind: 'unavailable' }
  | { kind: 'ready'; stub: ReturnType<NonNullable<Env['SPEND_LEDGER']>['getByName']> };

async function accessLedger(deviceToken: string, env: Env): Promise<LedgerAccess> {
  if (isLegacySharedToken(deviceToken)) {
    return { kind: 'legacy' };
  }
  if (!env.SPEND_LEDGER) {
    return { kind: 'unavailable' };
  }
  try {
    return { kind: 'ready', stub: env.SPEND_LEDGER.getByName(deviceLocator(deviceToken)) };
  } catch {
    return { kind: 'unavailable' };
  }
}

function emptySpendRecord(tokenHash: string, today: string): SpendRecord {
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
 * Get today's spend record for a device token (legacy tokens → empty in-memory shape).
 */
export async function getSpendRecord(
  deviceToken: string,
  env: Env
): Promise<SpendRecord> {
  const today = getTodayDateString();
  const tokenHash = await hashToken(deviceToken);
  const access = await accessLedger(deviceToken, env);

  if (access.kind === 'legacy' || access.kind === 'unavailable') {
    return emptySpendRecord(tokenHash, today);
  }

  const summary = await access.stub.summary(today, spendConfig(env));
  return {
    tokenHash,
    date: today,
    spentUSD: summary.spentUSD,
    reservedUSD: summary.reservedUSD,
    tasks: summary.byTask,
    lastUpdated: new Date().toISOString(),
  };
}

/**
 * Reserve an upper bound for a paid attempt (legacy shared tokens only → `no_ledger`).
 */
export async function reserveSpend(
  deviceToken: string,
  attemptId: string,
  upperBoundUSD: number,
  env: Env,
  day: string = getTodayDateString(),
  task = 'unknown'
): Promise<{ ok: boolean; reason?: string }> {
  const access = await accessLedger(deviceToken, env);
  if (access.kind === 'legacy') {
    return { ok: false, reason: 'no_ledger' };
  }
  if (access.kind === 'unavailable') {
    return { ok: false, reason: 'ledger_unavailable' };
  }
  return access.stub.reserve(attemptId, upperBoundUSD, day, spendConfig(env), task);
}

/**
 * Reconcile a reservation to the actual provider cost.
 */
export async function reconcileSpend(
  deviceToken: string,
  attemptId: string,
  actualUSD: number,
  env: Env,
  task?: string
): Promise<{ ok: boolean; reason?: string }> {
  const access = await accessLedger(deviceToken, env);
  if (access.kind === 'legacy') {
    return { ok: false, reason: 'no_ledger' };
  }
  if (access.kind === 'unavailable') {
    return { ok: false, reason: 'ledger_unavailable' };
  }
  return access.stub.reconcile(attemptId, actualUSD, task);
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
  const reserved = await reserveSpend(deviceToken, attemptId, costUSD, env, getTodayDateString(), task);
  if (!reserved.ok) return;
  await reconcileSpend(deviceToken, attemptId, costUSD, env, task);
}

/**
 * Check if hard cap is reached (triggers deterministic fallback).
 */
export async function isHardCapReached(
  deviceToken: string,
  env: Env
): Promise<boolean> {
  const access = await accessLedger(deviceToken, env);
  if (access.kind === 'unavailable') {
    return true;
  }
  if (access.kind === 'legacy') {
    return false;
  }
  const summary = await access.stub.summary(getTodayDateString(), spendConfig(env));
  return summary.hardCapReached;
}

/**
 * Check if soft threshold is reached (triggers secondary model).
 */
export async function isSoftThresholdReached(
  deviceToken: string,
  env: Env
): Promise<boolean> {
  const access = await accessLedger(deviceToken, env);
  if (access.kind === 'unavailable') {
    return true;
  }
  if (access.kind === 'legacy') {
    return false;
  }
  const summary = await access.stub.summary(getTodayDateString(), spendConfig(env));
  return summary.softThresholdReached;
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
  const access = await accessLedger(deviceToken, env);
  const config = spendConfig(env);

  if (access.kind === 'unavailable') {
    return {
      last7DaysUSD: 0,
      last30DaysUSD: 0,
      dailyCapUSD: config.dailyCapUSD,
      softThresholdUSD: config.softThresholdUSD,
      spentTodayUSD: 0,
      reservedTodayUSD: 0,
      softThresholdReached: true,
      hardCapReached: true,
      ledgerDayEndsAt: getEndOfDayISO(),
      byTask: {},
    };
  }

  if (access.kind === 'ready') {
    const summary = await access.stub.summary(getTodayDateString(), config);
    return {
      last7DaysUSD: summary.spentUSD,
      last30DaysUSD: summary.spentUSD,
      dailyCapUSD: config.dailyCapUSD,
      softThresholdUSD: config.softThresholdUSD,
      spentTodayUSD: summary.spentUSD,
      reservedTodayUSD: summary.reservedUSD,
      softThresholdReached: summary.softThresholdReached,
      hardCapReached: summary.hardCapReached,
      ledgerDayEndsAt: getEndOfDayISO(),
      byTask: summary.byTask,
    };
  }

  const record = await getSpendRecord(deviceToken, env);
  const totalSpent = record.spentUSD + record.reservedUSD;

  return {
    last7DaysUSD: record.spentUSD,
    last30DaysUSD: record.spentUSD,
    dailyCapUSD: config.dailyCapUSD,
    softThresholdUSD: config.softThresholdUSD,
    spentTodayUSD: record.spentUSD,
    reservedTodayUSD: record.reservedUSD,
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

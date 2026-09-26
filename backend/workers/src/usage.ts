/**
 * Usage tracking and spend cap enforcement via per-device Durable Object ledger (#13-a).
 */

import type { Env, SpendRecord, SpendLedgerAccess } from './types.js';
import { SPEND_CONFIG } from './types.js';
import { resolveSpendConfig, spendConfigFromEnv } from './spendConfig.js';
import { hashToken, deviceLocatorFromToken } from './tokens.js';

export { hashToken };

export type LedgerConfigStatus = 'ok' | 'config_error' | 'ledger_unavailable';

export interface UsageSummaryResponse {
  last7DaysUSD: number;
  last30DaysUSD: number;
  dailyCapUSD: number | null;
  softThresholdUSD: number | null;
  spentTodayUSD: number;
  reservedTodayUSD: number;
  softThresholdReached: boolean;
  hardCapReached: boolean;
  ledgerDayEndsAt: string | null;
  byTask: Record<string, number>;
  ledgerConfigStatus: LedgerConfigStatus;
}

function spendConfig(env: Env) {
  return spendConfigFromEnv(env);
}

function envConfigError(env: Env): boolean {
  return resolveSpendConfig(env).configError;
}

function failClosedUsageSummary(status: Exclude<LedgerConfigStatus, 'ok'>): UsageSummaryResponse {
  return {
    last7DaysUSD: 0,
    last30DaysUSD: 0,
    dailyCapUSD: null,
    softThresholdUSD: null,
    spentTodayUSD: 0,
    reservedTodayUSD: 0,
    softThresholdReached: true,
    hardCapReached: true,
    ledgerDayEndsAt: getEndOfDayISO(),
    byTask: {},
    ledgerConfigStatus: status,
  };
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

function emptySpendRecord(tokenHash: string, today: string, ledgerAccess: SpendLedgerAccess): SpendRecord {
  return {
    tokenHash,
    date: today,
    spentUSD: 0,
    reservedUSD: 0,
    tasks: {},
    lastUpdated: new Date().toISOString(),
    ledgerAccess,
  };
}

async function callLedger<T>(
  access: LedgerAccess,
  fn: (stub: NonNullable<Extract<LedgerAccess, { kind: 'ready' }>['stub']>) => Promise<T>
): Promise<T | 'unavailable'> {
  if (access.kind !== 'ready') {
    return 'unavailable';
  }
  try {
    return await fn(access.stub);
  } catch {
    return 'unavailable';
  }
}

export async function getSpendRecord(deviceToken: string, env: Env): Promise<SpendRecord> {
  const today = getTodayDateString();
  const tokenHash = await hashToken(deviceToken);
  const access = await accessLedger(deviceToken, env);

  if (access.kind === 'legacy') {
    return emptySpendRecord(tokenHash, today, 'legacy');
  }
  if (access.kind === 'unavailable' || envConfigError(env)) {
    return emptySpendRecord(tokenHash, today, 'unavailable');
  }

  const summary = await callLedger(access, (stub) => stub.summary(today, spendConfig(env)));
  if (summary === 'unavailable') {
    return emptySpendRecord(tokenHash, today, 'unavailable');
  }

  return {
    tokenHash,
    date: today,
    spentUSD: summary.spentUSD,
    reservedUSD: summary.reservedUSD,
    tasks: summary.byTask,
    lastUpdated: new Date().toISOString(),
    ledgerAccess: 'ok',
  };
}

export async function reserveSpend(
  deviceToken: string,
  attemptId: string,
  upperBoundUSD: number,
  env: Env,
  day: string = getTodayDateString(),
  task = 'unknown'
): Promise<{ ok: boolean; reason?: string }> {
  const access = await accessLedger(deviceToken, env);
  if (envConfigError(env)) {
    return { ok: false, reason: 'config_error' };
  }
  if (access.kind === 'unavailable') {
    return { ok: false, reason: 'ledger_unavailable' };
  }
  if (access.kind === 'legacy') {
    return { ok: false, reason: 'no_ledger' };
  }
  const result = await callLedger(access, (stub) =>
    stub.reserve(attemptId, upperBoundUSD, day, spendConfig(env), task)
  );
  if (result === 'unavailable') {
    return { ok: false, reason: 'ledger_unavailable' };
  }
  return result;
}

export async function reconcileSpend(
  deviceToken: string,
  attemptId: string,
  actualUSD: number,
  env: Env,
  task?: string
): Promise<{ ok: boolean; reason?: string }> {
  const access = await accessLedger(deviceToken, env);
  if (envConfigError(env)) {
    return { ok: false, reason: 'config_error' };
  }
  if (access.kind === 'unavailable') {
    return { ok: false, reason: 'ledger_unavailable' };
  }
  if (access.kind === 'legacy') {
    return { ok: false, reason: 'no_ledger' };
  }
  const result = await callLedger(access, (stub) => stub.reconcile(attemptId, actualUSD, task));
  if (result === 'unavailable') {
    return { ok: false, reason: 'ledger_unavailable' };
  }
  return result;
}

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

export async function isHardCapReached(deviceToken: string, env: Env): Promise<boolean> {
  const access = await accessLedger(deviceToken, env);
  if (access.kind === 'unavailable' || envConfigError(env)) {
    return true;
  }
  if (access.kind === 'legacy') {
    return false;
  }
  const summary = await callLedger(access, (stub) =>
    stub.summary(getTodayDateString(), spendConfig(env))
  );
  if (summary === 'unavailable') {
    return true;
  }
  return summary.hardCapReached;
}

export async function isSoftThresholdReached(deviceToken: string, env: Env): Promise<boolean> {
  const access = await accessLedger(deviceToken, env);
  if (access.kind === 'unavailable' || envConfigError(env)) {
    return true;
  }
  if (access.kind === 'legacy') {
    return false;
  }
  const summary = await callLedger(access, (stub) =>
    stub.summary(getTodayDateString(), spendConfig(env))
  );
  if (summary === 'unavailable') {
    return true;
  }
  return summary.softThresholdReached;
}

export async function getUsageSummary(
  deviceToken: string,
  env: Env
): Promise<UsageSummaryResponse> {
  const access = await accessLedger(deviceToken, env);

  if (envConfigError(env)) {
    return failClosedUsageSummary('config_error');
  }

  if (access.kind === 'unavailable') {
    return failClosedUsageSummary('ledger_unavailable');
  }

  if (access.kind === 'ready') {
    const config = spendConfig(env);
    const summary = await callLedger(access, (stub) =>
      stub.summary(getTodayDateString(), config)
    );
    if (summary === 'unavailable') {
      return failClosedUsageSummary('ledger_unavailable');
    }
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
      ledgerConfigStatus: 'ok',
    };
  }

  const record = await getSpendRecord(deviceToken, env);
  const totalSpent = record.spentUSD + record.reservedUSD;
  const resolved = resolveSpendConfig(env);
  const dailyCapUSD = resolved.configError ? null : resolved.dailyCapUSD;
  const softThresholdUSD = resolved.configError ? null : resolved.softThresholdUSD;

  return {
    last7DaysUSD: record.spentUSD,
    last30DaysUSD: record.spentUSD,
    dailyCapUSD,
    softThresholdUSD,
    spentTodayUSD: record.spentUSD,
    reservedTodayUSD: record.reservedUSD,
    softThresholdReached: totalSpent >= SPEND_CONFIG.softThresholdUSD,
    hardCapReached: totalSpent >= SPEND_CONFIG.dailyCapUSD,
    ledgerDayEndsAt: getEndOfDayISO(),
    byTask: record.tasks,
    ledgerConfigStatus: 'ok',
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

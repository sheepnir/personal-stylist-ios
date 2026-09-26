/**
 * Test-only reserve+reconcile helper (removed from production usage.ts — lossy id semantics).
 */

import { reconcileSpend, reserveSpend } from '../src/usage.js';
import type { Env } from '../src/types.js';

export type RecordSpendResult =
  | { ok: true }
  | { ok: false; stage: 'reserve' | 'reconcile'; reason: string };

function getTodayDateString(): string {
  return new Date().toISOString().split('T')[0];
}

/** Fixed attempt id from task + cost; second identical call hits already_settled on reserve. */
export async function recordSpend(
  deviceToken: string,
  task: string,
  costUSD: number,
  env: Env
): Promise<RecordSpendResult> {
  const attemptId = `test-record:${task}:${costUSD}`;
  const reservationDay = getTodayDateString();
  const reserved = await reserveSpend(deviceToken, attemptId, costUSD, env, reservationDay, task);
  if (!reserved.ok) {
    return { ok: false, stage: 'reserve', reason: reserved.reason ?? 'unknown' };
  }
  const reconciled = await reconcileSpend(deviceToken, attemptId, costUSD, env, task);
  if (!reconciled.ok) {
    return { ok: false, stage: 'reconcile', reason: reconciled.reason ?? 'unknown' };
  }
  return { ok: true };
}

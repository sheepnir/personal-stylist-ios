import type { DaySummary, ReconcileResult, ReserveResult } from './ledgerCore.js';

/** Keys that must not be copied onto a plain object (prototype pollution). */
const UNSAFE_RECORD_KEYS = new Set(['__proto__', 'constructor', 'prototype']);

/**
 * Copy a string-keyed record to a plain object safe for DO RPC / structured clone.
 * Skips unsafe keys; output always has `Object.prototype`.
 */
export function toRpcPlainRecord(source: Record<string, number>): Record<string, number> {
  const out: Record<string, number> = {};
  for (const key of Object.keys(source)) {
    if (UNSAFE_RECORD_KEYS.has(key)) {
      continue;
    }
    if (!Object.prototype.hasOwnProperty.call(source, key)) {
      continue;
    }
    out[key] = source[key]!;
  }
  return out;
}

export function toRpcDaySummary(summary: DaySummary): DaySummary {
  return {
    date: summary.date,
    spentUSD: summary.spentUSD,
    reservedUSD: summary.reservedUSD,
    softThresholdReached: summary.softThresholdReached,
    hardCapReached: summary.hardCapReached,
    overReservationCount: summary.overReservationCount,
    byTask: toRpcPlainRecord(summary.byTask),
  };
}

export function toRpcReserveResult(result: ReserveResult): ReserveResult {
  if (result.reason === undefined) {
    return { ok: result.ok };
  }
  return { ok: result.ok, reason: result.reason };
}

export function toRpcReconcileResult(result: ReconcileResult): ReconcileResult {
  if (result.reason === undefined) {
    return { ok: result.ok };
  }
  return { ok: result.ok, reason: result.reason };
}

/** Test helper: every nested object must use Object.prototype (RPC-safe). */
export function assertRpcPlainDeep(value: unknown, path = 'root'): void {
  if (value === null || value === undefined) {
    return;
  }
  if (typeof value === 'number' || typeof value === 'string' || typeof value === 'boolean') {
    return;
  }
  if (Array.isArray(value)) {
    value.forEach((item, index) => assertRpcPlainDeep(item, `${path}[${index}]`));
    return;
  }
  if (typeof value !== 'object') {
    return;
  }
  if (Object.getPrototypeOf(value) !== Object.prototype) {
    throw new Error(`${path}: expected Object.prototype, got ${String(Object.getPrototypeOf(value))}`);
  }
  for (const key of Object.keys(value as object)) {
    assertRpcPlainDeep((value as Record<string, unknown>)[key], `${path}.${key}`);
  }
}

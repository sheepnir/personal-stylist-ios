import type { DeviceTokenRegistry } from './tokenRegistry.js';
import type { DeviceSpendLedger } from './spendLedger.js';
/**
 * Cloudflare Workers environment bindings for Personal Stylist backend (M0-09).
 */

export interface Env extends Omit<Cloudflare.Env, "REQUEST_RATE_LIMITER" | "DEVICE_TOKENS" | "SPEND_LEDGER"> {
  DEVICE_TOKENS?: DurableObjectNamespace<DeviceTokenRegistry>;
  /** Per-device spend ledger (keyed by device locator id). */
  SPEND_LEDGER?: DurableObjectNamespace<DeviceSpendLedger>;
  /** Platform abuse throttle; missing binding fails closed. */
  REQUEST_RATE_LIMITER?: Cloudflare.Env["REQUEST_RATE_LIMITER"];
  /** KV namespace for usage ledger (device token → day → spend). */
  USAGE_LEDGER: KVNamespace;
  
  /** OpenRouter API key (secret). */
  OPENROUTER_API_KEY: string;
  
  /**
   * Enrollment secret for `POST /v1/auth/device` only (D-46).
   * Never authenticates content endpoints.
   */
  ENROLLMENT_SECRET?: string;

  /**
   * Legacy shared device token. Honoured only when this secret is configured.
   * Prefer per-device tokens issued via ENROLLMENT_SECRET.
   */
  DEVICE_TOKEN?: string;
  
  /** Optional: environment name (staging/production). */
  ENVIRONMENT?: Cloudflare.Env["ENVIRONMENT"];

  /**
   * Optional comma-separated allowlist of browser origins permitted for CORS.
   * When unset, no Access-Control-Allow-Origin header is emitted (the native
   * client does not need CORS). Never use `*`.
   */
  ALLOWED_ORIGINS?: string;

  /** Optional: daily hard spend cap in USD (plain-text var). Defaults to the sample value. */
  DAILY_CAP_USD?: string;

  /** Optional: soft spend threshold in USD (plain-text var). Defaults to the sample value. */
  SOFT_THRESHOLD_USD?: string;

  /** Optional: URL sent as the provider attribution `HTTP-Referer`. Defaults to a reserved example. */
  ATTRIBUTION_URL?: string;
}

/**
 * Problem detail shape (RFC 9457 + extensions).
 */
export interface ProblemDetail {
  type?: string;
  title: string;
  status: number;
  detail: string;
  code?: string;
  dataPreserved?: boolean;
  [key: string]: unknown;
}

/**
 * Spend state for usage tracking.
 */
export type SpendLedgerAccess = 'ok' | 'legacy' | 'unavailable';

export interface SpendRecord {
  /**
   * SHA-256 hash (hex) of the device token for correlating API responses only;
   * never stored in the Durable Object spend ledger (#174).
   */
  tokenHash: string;
  date: string; // YYYY-MM-DD
  spentUSD: number;
  reservedUSD: number;
  tasks: Record<string, number>; // task -> cost
  lastUpdated: string; // ISO timestamp
  /** Distinguishes legacy (no ledger), unavailable (fail-closed), and normal reads. */
  ledgerAccess: SpendLedgerAccess;
}

/**
 * Daily spend cap configuration.
 *
 * SAMPLE defaults for illustration only — they are not recommendations. Set your own per
 * deployment with the `DAILY_CAP_USD` / `SOFT_THRESHOLD_USD` vars (wrangler.toml `[vars]`
 * or the dashboard); see `resolveSpendConfig`.
 */
export const SPEND_CONFIG = {
  dailyCapUSD: 1.0,
  softThresholdUSD: 0.5,
} as const;

export interface SpendConfig {
  dailyCapUSD: number;
  softThresholdUSD: number;
}

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
 * `DAILY_CAP_USD` or `SOFT_THRESHOLD_USD` is a config error (fail closed, no silent fallback).
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

  const softParsed = parsePlainDecimalUsd(env.SOFT_THRESHOLD_USD);
  if (softParsed === null) {
    logSpendConfigError();
    return { configError: true };
  }
  const softThresholdUSD = Math.min(
    softParsed === 'unset' ? SPEND_CONFIG.softThresholdUSD : softParsed,
    dailyCapUSD
  );
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

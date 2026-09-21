import type { DeviceTokenRegistry } from './tokenRegistry.js';
/**
 * Cloudflare Workers environment bindings for Personal Stylist backend (M0-09).
 */

export interface Env extends Omit<Cloudflare.Env, "REQUEST_RATE_LIMITER" | "DEVICE_TOKENS"> {
  DEVICE_TOKENS?: DurableObjectNamespace<DeviceTokenRegistry>;
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
export interface SpendRecord {
  /**
   * SHA-256 hash (hex) of the device token. The raw token is never persisted
   * in the ledger value (#174); only this non-reversible identifier is stored.
   */
  tokenHash: string;
  date: string; // YYYY-MM-DD
  spentUSD: number;
  reservedUSD: number;
  tasks: Record<string, number>; // task -> cost
  lastUpdated: string; // ISO timestamp
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

/**
 * Resolve the spend config for this deployment: valid positive env vars win over the sample
 * defaults; the soft threshold is clamped to the hard cap.
 */
export function resolveSpendConfig(
  env: Pick<Env, 'DAILY_CAP_USD' | 'SOFT_THRESHOLD_USD'>
): SpendConfig {
  const parse = (raw: string | undefined, fallback: number): number => {
    const n = raw === undefined || raw.trim() === '' ? NaN : Number(raw);
    return Number.isFinite(n) && n > 0 ? n : fallback;
  };
  const dailyCapUSD = parse(env.DAILY_CAP_USD, SPEND_CONFIG.dailyCapUSD);
  const soft = parse(env.SOFT_THRESHOLD_USD, SPEND_CONFIG.softThresholdUSD);
  return { dailyCapUSD, softThresholdUSD: Math.min(soft, dailyCapUSD) };
}

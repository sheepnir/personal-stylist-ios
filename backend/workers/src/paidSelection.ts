import type { Env, SpendConfig } from './types.js';
import type { AuthContext } from './auth.js';
import type { ContextSnapshot } from '@personal-stylist/outfit-engine';
import { deviceLocatorFromToken } from './tokens.js';
import { spendConfigFromEnv } from './spendConfig.js';
import { capUsdToMicro } from './ledgerCore.js';
import { boundedJSON, costBound, fetchPrice, JEV_MODEL, JEV_PROMPT_VERSION, object, POLICY_VERSION, requestBody, validateDecision, type Candidate } from './jev.js';

export async function boundedLedger<T>(promise: Promise<T>, milliseconds = 600): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try { return await Promise.race([promise, new Promise<never>((_, reject) => { timer = setTimeout(() => reject(new Error('LEDGER_TIMEOUT')), milliseconds); })]); }
  finally { if (timer !== undefined) clearTimeout(timer); }
}
export const GLOBAL_LEDGER_NAME = 'application-spend-v1';
export function strictCap(raw: string | undefined): number | null {
  if (raw === undefined || !/^\d+(\.\d+)?$/.test(raw)) return null;
  const value = Number(raw);
  return value > 0 && value <= 100 && capUsdToMicro(value).ok ? value : null;
}
export type Provenance = { modelId: string; promptVersion: string; fallbackLevel: 'NONE' | 'DETERMINISTIC';
  fallbackReason?: 'PROVIDER_ERROR' | 'INVALID_OUTPUT' | 'SPEND_CAP'; costUSD: number | null;
  inputTokens?: unknown; outputTokens?: unknown; spendState?: string; latencyMs: number };
export type Selection<T> = { result: T; provenance?: Provenance };

export function eligible(env: Env, auth: AuthContext, accepted: unknown): boolean {
  const locator = deviceLocatorFromToken(auth.deviceToken);
  return env.PROVIDER_GENERATION === 'live' && ['production', 'staging'].includes(env.ENVIRONMENT ?? '') &&
    !auth.legacyShared && locator !== null && accepted === POLICY_VERSION &&
    env.PROVIDER_POLICY_VERIFIED_ON !== undefined && /^\d{4}-\d{2}-\d{2}$/.test(env.PROVIDER_POLICY_VERIFIED_ON) &&
    env.PROVIDER_KEY_LIMIT_VERIFIED === 'true' &&
    (env.PROVIDER_GENERATION_DEVICES === undefined || env.PROVIDER_GENERATION_DEVICES.split(',').includes(locator));
}
/** Same selection/reservation path for generate and swap. No provider retry. */
export async function selectPaid<T>(args: {
  candidates: Candidate<T>[]; fallback: T; context: ContextSnapshot; acceptedPolicy: unknown;
  env: Env; auth: AuthContext; task: 'jev-generate' | 'jev-swap'; fetcher?: typeof fetch;
}): Promise<Selection<T>> {
  const { candidates, fallback, context, acceptedPolicy, env, auth, task } = args;
  if (!eligible(env, auth, acceptedPolicy) || candidates.length < 2) return { result: fallback };
  const started = Date.now();
  const fail = (reason: NonNullable<Provenance['fallbackReason']>): Selection<T> => ({ result: fallback, provenance: {
    modelId: 'deterministic-v0', promptVersion: 'none', fallbackLevel: 'DETERMINISTIC', fallbackReason: reason,
    costUSD: null, latencyMs: Date.now() - started,
    ...(reason === 'SPEND_CAP' ? { spendState: 'HARD_CAP_DETERMINISTIC' } : {}),
  } });
  const log = (outcome: string) => console.info(JSON.stringify({ modelId: JEV_MODEL, promptVersion: JEV_PROMPT_VERSION, outcome, latencyMs: Date.now() - started }));
  const fetcher = args.fetcher ?? fetch;
  if (env.PRIMARY_MODEL !== JEV_MODEL || !env.OPENROUTER_API_KEY) { log('MODEL_NOT_ALLOWED'); return fail('PROVIDER_ERROR'); }
  let price, body: string, ceiling: number;
  try {
    price = await fetchPrice(fetcher);
    ceiling = Math.max(0.000001, costBound(price));
    if (!Number.isFinite(ceiling) || ceiling <= 0 || ceiling > 1) throw new Error('COST_BOUND');
    body = requestBody(candidates, context, price);
  } catch { log('MODEL_UNAVAILABLE'); return fail('PROVIDER_ERROR'); }
  const cap = strictCap(env.GLOBAL_DAILY_CAP_USD), total = strictCap(env.EVALUATION_TOTAL_CAP_USD);
  if (strictCap(env.DAILY_CAP_USD) === null || cap === null || total === null || !env.SPEND_LEDGER) { log('CAP_CONFIGURATION'); return fail('SPEND_CAP'); }
  const device = env.SPEND_LEDGER.getByName(deviceLocatorFromToken(auth.deviceToken)!);
  const global = env.SPEND_LEDGER.getByName(GLOBAL_LEDGER_NAME);
  const day = new Date().toISOString().slice(0, 10), attempt = crypto.randomUUID();
  const config: SpendConfig = { dailyCapUSD: cap, softThresholdUSD: cap };
  let deviceReserved = false;
  let softThresholdReached = false;
  try {
    // The global switch is read from a strongly consistent object on every request.
    if (!(await boundedLedger(global.providerEnabled()))) return { result: fallback };
    const configDevice = spendConfigFromEnv(env);
    const summary = await boundedLedger(device.summary(day, configDevice));
    softThresholdReached = summary.softThresholdReached;
    const reserved = await boundedLedger(device.reserve(attempt, ceiling, day, configDevice, task));
    if (reserved?.ok !== true) { log('DEVICE_CAP_OR_LEDGER'); return fail('SPEND_CAP'); }
    deviceReserved = true;
    const reservedGlobal = await boundedLedger(global.reserveGlobal(attempt, ceiling, day, config, total, task));
    if (reservedGlobal?.ok !== true) throw new Error('GLOBAL_CAP_OR_LEDGER');
  } catch {
    if (deviceReserved) await boundedLedger(device.reconcile(day, attempt, 0, task)).catch(() => {});
    log('GLOBAL_CAP_OR_LEDGER'); return fail('SPEND_CAP');
  }
  // Once both reservations are acknowledged, failures retain conservative holds.
  let raw: unknown;
  try {
    const response = await fetcher('https://openrouter.ai/api/alpha/decisions', {
      method: 'POST', headers: { Authorization: `Bearer ${env.OPENROUTER_API_KEY}`, 'Content-Type': 'application/json' },
      body, signal: AbortSignal.timeout(8000),
    });
    if (!response.ok) { await response.body?.cancel(); throw new Error('PROVIDER_HTTP'); }
    raw = await boundedJSON(response);
  } catch {
    await Promise.allSettled([boundedLedger(device.markUnknown(day, attempt)), boundedLedger(global.markUnknown(day, attempt))]);
    log('PROVIDER_ERROR'); return fail('PROVIDER_ERROR');
  }
  const response = object(raw), usage = object(response.usage);
  const cost = typeof usage.cost === 'number' && Number.isFinite(usage.cost) && usage.cost >= 0 ? usage.cost : null;
  const generationId = typeof response.id === 'string' && /^[a-zA-Z0-9_-]{1,128}$/.test(response.id) ? response.id : undefined;
  if (cost !== null) {
    const settled = await Promise.allSettled([boundedLedger(device.reconcile(day, attempt, cost, task)), boundedLedger(global.reconcile(day, attempt, cost, task))]);
    await Promise.allSettled([device, global].map(async (ledger, index) => {
      const result = settled[index];
      if (result.status !== 'fulfilled' || result.value?.ok !== true) await boundedLedger(ledger.markUnknown(day, attempt, generationId));
    }));
  } else {
    await Promise.allSettled([boundedLedger(device.markUnknown(day, attempt, generationId)), boundedLedger(global.markUnknown(day, attempt, generationId))]);
  }
  if (cost !== null && cost > ceiling) {
    await boundedLedger(global.setProviderEnabled(false)).catch(() => {});
    log('COST_OVER_RESERVATION'); return fail('PROVIDER_ERROR');
  }
  try {
    const decision = validateDecision(raw, candidates);
    log('MODEL_SELECTED');
    return { result: decision.result, provenance: { modelId: decision.model, promptVersion: JEV_PROMPT_VERSION,
      fallbackLevel: 'NONE', costUSD: cost, inputTokens: decision.inputTokens, outputTokens: decision.outputTokens,
      spendState: softThresholdReached ? 'SOFT_THRESHOLD' : 'OK', latencyMs: Date.now() - started } };
  } catch { log('INVALID_OUTPUT'); return fail('INVALID_OUTPUT'); }
}

import { describe, expect, it, vi } from 'vitest';
import { createDeviceSpendLedgerHarness } from './helpers.js';
import { GLOBAL_LEDGER_NAME, selectPaid } from '../src/paidSelection.js';
import { JEV_MODEL, POLICY_VERSION } from '../src/jev.js';
import { LUNA_MODEL, LUNA_POLICY } from '../src/luna.js';
import type { Env } from '../src/types.js';

const locator = '11111111-1111-4111-8111-111111111111';
const context = { occasion: 'WORK_STANDARD', occasionFormality: 3, temperatureBand: 'MILD' as const };
const candidates = ['a', 'b'].map(token => ({ token, result: token, garments: [] }));
const policyFor = (model: string) => model === JEV_MODEL ? POLICY_VERSION : LUNA_POLICY;
function rig(caps: { device?: string; global?: string; total?: string } = {}) {
  // Real ledger logic with in-memory storage; workerd persistence has separate runtime coverage.
  const device = createDeviceSpendLedgerHarness().ledger;
  const global = createDeviceSpendLedgerHarness().ledger;
  global.setProviderEnabled(true);
  const names: string[] = [];
  const env = { PROVIDER_GENERATION: 'live', ENVIRONMENT: 'staging', PRIMARY_MODEL: JEV_MODEL,
    LUNA_COMPARISON: 'enabled', OPENROUTER_API_KEY: 'synthetic', DAILY_CAP_USD: caps.device ?? '1',
    GLOBAL_DAILY_CAP_USD: caps.global ?? '1', EVALUATION_TOTAL_CAP_USD: caps.total ?? '1',
    SOFT_THRESHOLD_USD: '0.01', PROVIDER_POLICY_VERIFIED_ON: '2030-01-01', PROVIDER_KEY_LIMIT_VERIFIED: 'true',
    SPEND_LEDGER: { getByName(name: string) { names.push(name); return name === GLOBAL_LEDGER_NAME ? global : device; } },
  } as unknown as Env;
  const posts: { url: string; model: string }[] = [];
  const fetcher = vi.fn(async (url: string | URL | Request, init?: RequestInit) => {
    const address = String(url);
    if (address.endsWith('/endpoints')) {
      const luna = address.includes(LUNA_MODEL);
      return Response.json({ data: { id: luna ? LUNA_MODEL : JEV_MODEL, endpoints: [{
        tag: luna ? 'openai' : 'typesafe', status: 0, context_length: 32000,
        max_completion_tokens: luna ? 1024 : 0,
        supported_parameters: ['structured_outputs', 'response_format', 'max_tokens', 'reasoning'],
        pricing: { prompt: '0.000001', completion: luna ? '0.000001' : '0' },
      }] } });
    }
    const body = JSON.parse(String(init?.body));
    posts.push({ url: address, model: body.model });
    if (body.model === LUNA_MODEL) return Response.json({ model: LUNA_MODEL,
      choices: [{ finish_reason: 'stop', message: { content: '{"choice":"b"}' } }],
      usage: { prompt_tokens: 100, completion_tokens: 10, cost: 0.025 } });
    return Response.json({ model: JEV_MODEL,
      answers: { outfit: { type: 'choice', choice: 'a', confidence: 1, probabilities: { a: 1, b: 0 } } },
      usage: { input_tokens: 100, output_tokens: 0, cost: 0.025 } });
  });
  const run = (model: string, policy: unknown = policyFor(model), task: 'jev-generate' | 'jev-swap' = 'jev-generate') =>
    selectPaid({ candidates, fallback: 'rules', context, selectedModel: model, acceptedPolicy: policy, env,
      auth: { deviceToken: locator + '.' + 'a'.repeat(43), legacyShared: false }, task, fetcher });
  return { run, device, global, names, posts, fetcher };
}

describe('Jev/Luna isolation and shared accounting', () => {
  it.each([JEV_MODEL, LUNA_MODEL])('selection %s uses only its endpoint and preserves accounting', async first => {
    const s = rig();
    const second = first === JEV_MODEL ? LUNA_MODEL : JEV_MODEL;
    for (const model of [first, second]) expect((await s.run(model, policyFor(model), 'jev-swap')).provenance?.modelId).toBe(model);
    expect(s.posts).toEqual([first, second].map(model => ({ model,
      url: model === LUNA_MODEL ? 'https://openrouter.ai/api/v1/chat/completions' : 'https://openrouter.ai/api/alpha/decisions' })));
    expect(s.names).toEqual([locator, GLOBAL_LEDGER_NAME, locator, GLOBAL_LEDGER_NAME]);
    const day = new Date().toISOString().slice(0, 10);
    for (const ledger of [s.device, s.global]) {
      const summary = ledger.summary(day, { dailyCapUSD: 1, softThresholdUSD: 0.5 });
      expect(summary.spentUSD).toBe(0.05);
      expect(summary.byTask).toEqual({ 'jev-swap': 0.025, 'luna-swap': 0.025 });
    }
  });
  it.each((['device', 'global', 'total'] as const).flatMap(scope => [JEV_MODEL, LUNA_MODEL].map(first => ({ scope, first }))))('switching from $first cannot bypass shared $scope cap', async ({ scope, first }) => {
    const s = rig({ [scope]: '0.05' });
    const second = first === JEV_MODEL ? LUNA_MODEL : JEV_MODEL;
    expect((await s.run(first)).provenance?.modelId).toBe(first);
    expect((await s.run(second)).provenance?.fallbackReason).toBe('SPEND_CAP');
    expect(s.posts).toHaveLength(1);
    const day = new Date().toISOString().slice(0, 10);
    expect(s.device.summary(day, { dailyCapUSD: 1, softThresholdUSD: 0.5 }).reservedUSD).toBe(0);
  });
  it.each([[JEV_MODEL, LUNA_POLICY], [LUNA_MODEL, POLICY_VERSION], [LUNA_MODEL, ''], ['unapproved/model', LUNA_POLICY]])
    ('rejects cross-model/missing consent %s/%s before any fetch', async (model, policy) => {
      const s = rig();
      expect(await s.run(model, policy)).toEqual({ result: 'rules' });
      expect(s.fetcher).not.toHaveBeenCalled();
      expect(s.names).toEqual([]);
    });
  it('switching back cannot use Luna consent to authorize Jev', async () => {
    const s = rig();
    expect((await s.run(LUNA_MODEL)).provenance?.modelId).toBe(LUNA_MODEL);
    expect(await s.run(JEV_MODEL, LUNA_POLICY)).toEqual({ result: 'rules' });
    expect(s.posts.map(post => post.model)).toEqual([LUNA_MODEL]);
  });
});

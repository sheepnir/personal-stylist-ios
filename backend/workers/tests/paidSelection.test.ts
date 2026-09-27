import { describe, it, expect, vi } from 'vitest';
import { boundedLedger, selectPaid, GLOBAL_LEDGER_NAME } from '../src/paidSelection.js';
import { JEV_MODEL, POLICY_VERSION, requestBody, validateDecision, costBound, fetchPrice, type Candidate } from '../src/jev.js';
import type { Env } from '../src/types.js';
import { emptyLedger } from './helpers.js';

const context = { occasion: 'WORK_STANDARD', occasionFormality: 3, temperatureBand: 'MILD' as const };
const candidates: Candidate<string>[] = ['a', 'b'].map((token, i) => ({ token, result: token,
  garments: [{ id: `secret-id-${i}`, displayName: 'PRIVATE NAME', slot: 'TOP', colorPrimary: {family: 'navy', name: 'PRIVATE COLOR', hex: '#private'}, formality: 3, warmth: 2 }] }));
const price = { prompt: 0.000000042, completion: 0, context: 32000, maxOutput: 28800 };
function answer(choice = 'b') { return { model: JEV_MODEL, id: 'gen-synthetic', answers: { outfit: {type:'choice', choice, confidence:0.8, probabilities:{a:0.1,b:0.9}} }, usage:{input_tokens:100,output_tokens:20,cost:0.00001} }; }
function setup() {
  const calls: string[] = [];
  const device = { summary:vi.fn(async () => ({softThresholdReached:false})), reserve: vi.fn(async () => { calls.push('device'); return {ok:true}; }), reconcile:vi.fn(async () => ({ok:true})), markUnknown:vi.fn(async () => ({ok:true})) };
  const global = { providerEnabled:vi.fn(async () => true), setProviderEnabled:vi.fn(async () => {}), reserveGlobal:vi.fn(async () => { calls.push('global'); return {ok:true}; }), reconcile:vi.fn(async () => ({ok:true})), markUnknown:vi.fn(async () => ({ok:true})) };
  const env = { OPENROUTER_API_KEY:'synthetic', USAGE_LEDGER:emptyLedger(), PROVIDER_GENERATION:'live', ENVIRONMENT:'staging', PRIMARY_MODEL:JEV_MODEL,
    DAILY_CAP_USD:'1', SOFT_THRESHOLD_USD:'0.5', GLOBAL_DAILY_CAP_USD:'1', EVALUATION_TOTAL_CAP_USD:'2', PROVIDER_POLICY_VERIFIED_ON:'2026-09-27', PROVIDER_KEY_LIMIT_VERIFIED:'true',
    SPEND_LEDGER:{getByName:(name:string) => name === GLOBAL_LEDGER_NAME ? global : device} } as unknown as Env;
  const fetcher = vi.fn(async (url: string | URL | Request) => {
    if (String(url).endsWith('/endpoints')) return Response.json({data:{id:JEV_MODEL,endpoints:[{tag:'typesafe',status:0,context_length:32000,max_completion_tokens:28800,pricing:{prompt:'0.000000042',completion:'0'}}]}});
    calls.push('provider'); return Response.json(answer());
  });
  const auth = {deviceToken:'11111111-1111-4111-8111-111111111111.'+'a'.repeat(43),legacyShared:false};
  const run = (acceptedPolicy:unknown = POLICY_VERSION) => selectPaid({candidates, fallback:'deterministic', context, acceptedPolicy, env, auth, task:'jev-generate', fetcher});
  return {device,global,env,fetcher,auth,run,calls};
}
describe('bounded typed selection', () => {
  it('calls only after both reservations and returns honest provenance', async () => {
    const s=setup(); const result=await s.run();
    expect(s.calls).toEqual(['device','global','provider']);
    expect(result.result).toBe('b'); expect(result.provenance?.fallbackLevel).toBe('NONE');
    expect(s.device.reconcile).toHaveBeenCalled(); expect(s.global.reconcile).toHaveBeenCalled();
    const init=s.fetcher.mock.calls[1]; expect(init).toBeDefined();
  });
  it.each([undefined, null, '', 'wrong', 'JEV-TEXT-V1'])('does not call or reserve without exact consent %s',async v=>{
    const s=setup(); await s.run(v===undefined ? null : v); expect(s.fetcher).not.toHaveBeenCalled(); expect(s.device.reserve).not.toHaveBeenCalled();
  });
  it.each(['off','mock','LIVE','',undefined])('fails closed on flag %s',async flag=>{
    const s=setup();s.env.PROVIDER_GENERATION=flag;await s.run();expect(s.fetcher).not.toHaveBeenCalled();
  });
  it('legacy auth and missing verification are never eligible',async()=>{
    const s=setup();s.auth.legacyShared=true;await s.run();expect(s.fetcher).not.toHaveBeenCalled();
    s.auth.legacyShared=false;s.env.PROVIDER_KEY_LIMIT_VERIFIED=undefined;await s.run();expect(s.fetcher).not.toHaveBeenCalled();
  });
  it('unallowlisted model touches neither ledger nor provider',async()=>{
    const s=setup();s.env.PRIMARY_MODEL='other';expect((await s.run()).provenance?.fallbackReason).toBe('PROVIDER_ERROR');expect(s.fetcher).not.toHaveBeenCalled();expect(s.device.reserve).not.toHaveBeenCalled();
  });
  it('device refusal never reserves global or calls provider',async()=>{
    const s=setup();s.device.reserve.mockResolvedValue({ok:false});expect((await s.run()).provenance?.fallbackReason).toBe('SPEND_CAP');expect(s.calls).not.toContain('provider');expect(s.global.reserveGlobal).not.toHaveBeenCalled();
  });
  it('global failure releases known unsent device hold',async()=>{
    const s=setup();s.global.reserveGlobal.mockRejectedValue(new Error('failure'));await s.run();expect(s.calls).not.toContain('provider');expect(s.device.reconcile.mock.calls[0]?.[2]).toBe(0);
  });
  it('missing cap fails closed',async()=>{
    const s=setup();s.env.GLOBAL_DAILY_CAP_USD=undefined;await s.run();expect(s.device.reserve).not.toHaveBeenCalled();expect(s.calls).not.toContain('provider');
  });
  it('disabled runtime switch prevents reservations',async()=>{
    const s=setup();s.global.providerEnabled.mockResolvedValue(false);await s.run();expect(s.device.reserve).not.toHaveBeenCalled();expect(s.calls).not.toContain('provider');
  });
  it('network timeout retains unknown holds without retry',async()=>{
    const s=setup();s.fetcher.mockImplementationOnce(async()=>Response.json({data:{id:JEV_MODEL,endpoints:[{tag:'typesafe',status:0,context_length:32000,max_completion_tokens:28800,pricing:{prompt:'0.000000042',completion:'0'}}]}})).mockRejectedValueOnce(new Error('private provider error'));
    expect((await s.run()).provenance?.fallbackReason).toBe('PROVIDER_ERROR');expect(s.fetcher).toHaveBeenCalledTimes(2);expect(s.device.markUnknown).toHaveBeenCalled();expect(s.global.markUnknown).toHaveBeenCalled();expect(s.device.reconcile).not.toHaveBeenCalled();
  });
  it('invalid output still accounts for cost and falls back',async()=>{
    const s=setup();const original=s.fetcher.getMockImplementation()!;
    s.fetcher.mockImplementation(async u=>String(u).endsWith('/endpoints')?original(u):Response.json(answer('invented')));
    expect((await s.run()).provenance?.fallbackReason).toBe('INVALID_OUTPUT');expect(s.device.reconcile).toHaveBeenCalled();
  });
  it('missing cost retains generation reference',async()=>{
    const s=setup();const original=s.fetcher.getMockImplementation()!;
    s.fetcher.mockImplementation(async u=>{if(String(u).endsWith('/endpoints'))return original(u);const a=answer();delete (a.usage as {cost?:number}).cost;return Response.json(a);});
    expect((await s.run()).provenance?.costUSD).toBeNull();expect(s.global.markUnknown.mock.calls[0]?.[2]).toBe('gen-synthetic');
  });
  it('constructs minimum payload; strips arbitrary values and private fields',()=>{
    const body=requestBody(candidates,{...context,freeTextNote:'PRIVATE NOTE'},price);
    expect(body).not.toMatch(/PRIVATE|secret-id|displayName|freeTextNote|hex/);
    expect(JSON.parse(body).provider).toMatchObject({data_collection:'deny',allow_fallbacks:false,require_parameters:true});
    expect(costBound(price)).toBe(0.001344);
  });
  it('rejects unknown choices, answers, models and malformed probabilities',()=>{
    expect(()=>validateDecision(answer('invented'),candidates)).toThrow();
    const a=answer();a.model='other';expect(()=>validateDecision(a,candidates)).toThrow();
    const b=answer();b.answers.outfit.confidence=NaN;expect(()=>validateDecision(b,candidates)).toThrow();
    const c=answer();c.answers.outfit.probabilities.b=5;expect(()=>validateDecision(c,candidates)).toThrow();
  });
  it('unpriced listing never treats absent or negative price as zero',async()=>{
    for(const completion of [undefined,null,'-1','oops']) {
      await expect(fetchPrice(async()=>Response.json({data:{id:JEV_MODEL,endpoints:[{tag:'typesafe',status:0,context_length:32000,max_completion_tokens:28800,pricing:{prompt:'0.000000042',completion}}]}}))).rejects.toThrow();
    }
  });
});

it('bounds an unresponsive ledger without claiming cancellation', async () => {
  await expect(boundedLedger(new Promise(() => {}), 5)).rejects.toThrow('LEDGER_TIMEOUT');
});
it('reports the soft threshold without blocking a valid model choice', async () => {
  const s = setup(); s.device.summary.mockResolvedValue({softThresholdReached: true});
  expect((await s.run()).provenance?.spendState).toBe('SOFT_THRESHOLD');
});

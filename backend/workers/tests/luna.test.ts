import { describe, it, expect, vi } from 'vitest';
import { fetchLunaPrice, lunaRequestBody, validateLuna, LUNA_MODEL, LUNA_POLICY } from '../src/luna.js';
import { eligible, selectPaid, GLOBAL_LEDGER_NAME } from '../src/paidSelection.js';
import { JEV_MODEL, POLICY_VERSION, costBound } from '../src/jev.js';
import type { Env } from '../src/types.js';
const context = { occasion:'WORK_STANDARD', occasionFormality:3, temperatureBand:'MILD' as const };
const candidates = ['a','b'].map(token => ({token,result:token,garments:[{id:'PRIVATE ID',displayName:'PRIVATE NAME',slot:'TOP',formality:3,warmth:2}]}));
const endpoint = {tag:'openai',status:0,context_length:1050000,max_completion_tokens:128000,supported_parameters:['structured_outputs','response_format','max_tokens','reasoning'],pricing:{prompt:'0.0000002',completion:'0.0000012'}};
function answer() { return {model:'openai/gpt-5.6-luna-20260709', id:'gen-synthetic', choices:[{finish_reason:'stop',message:{content:'{"choice":"b"}'}}],usage:{prompt_tokens:100,completion_tokens:30,cost:0.000056}}; }
function setup() {
  const calls:string[]=[];
  const device={summary:vi.fn(async()=>({softThresholdReached:false})),reserve:vi.fn(async()=>{calls.push('device');return {ok:true};}),reconcile:vi.fn(async()=>({ok:true})),markUnknown:vi.fn(async()=>({ok:true}))};
  const global={providerEnabled:vi.fn(async()=>true),setProviderEnabled:vi.fn(async()=>{}),reserveGlobal:vi.fn(async()=>{calls.push('global');return {ok:true};}),reconcile:vi.fn(async()=>({ok:true})),markUnknown:vi.fn(async()=>({ok:true}))};
  const env={PROVIDER_GENERATION:'live',ENVIRONMENT:'staging',PRIMARY_MODEL:JEV_MODEL,LUNA_COMPARISON:'enabled',OPENROUTER_API_KEY:'synthetic',DAILY_CAP_USD:'1',GLOBAL_DAILY_CAP_USD:'1',SOFT_THRESHOLD_USD:'0.5',EVALUATION_TOTAL_CAP_USD:'2',PROVIDER_POLICY_VERIFIED_ON:'2026-09-27',PROVIDER_KEY_LIMIT_VERIFIED:'true',SPEND_LEDGER:{getByName:(name:string)=>name===GLOBAL_LEDGER_NAME?global:device}} as unknown as Env;
  const auth={deviceToken:'11111111-1111-4111-8111-111111111111.'+'a'.repeat(43),legacyShared:false};
  const fetcher=vi.fn(async(url:string|URL|Request,_init?:RequestInit)=>{if(String(url).endsWith('/endpoints'))return Response.json({data:{id:LUNA_MODEL,endpoints:[endpoint]}});calls.push('provider');return Response.json(answer());});
  const run=(acceptedPolicy:unknown=LUNA_POLICY)=>selectPaid({candidates,fallback:'rules',context,acceptedPolicy,selectedModel:LUNA_MODEL,env,auth,task:'jev-generate',fetcher});
  return {env,auth,fetcher,device,global,calls,run};
}
describe('Luna bounded comparison',()=>{
  it('uses the common ledger before exactly one Luna call and accounts for actual cost',async()=>{
    const s=setup();const result=await s.run();expect(s.calls).toEqual(['device','global','provider']);expect(result.result).toBe('b');expect(result.provenance).toMatchObject({modelId:'openai/gpt-5.6-luna-20260709',fallbackLevel:'NONE',promptVersion:'outfit-choice-luna-v1'});
    expect(s.fetcher.mock.calls[1][0]).toBe('https://openrouter.ai/api/v1/chat/completions');
    expect(s.device.reserve.mock.calls[0]?.[4]).toBe('luna-generate');
    expect(s.device.reconcile.mock.calls[0]?.[2]).toBe(0.000056);expect(s.global.reconcile).toHaveBeenCalled();
  });
  it.each([null,'',POLICY_VERSION,'LUNA-TEXT-V1'])('requires separate exact consent %s',async policy=>{
    const s=setup();await s.run(policy);expect(s.fetcher).not.toHaveBeenCalled();expect(s.device.reserve).not.toHaveBeenCalled();
  });
  it('cannot bypass deployment, device allowlist, or runtime switch',async()=>{
    const s=setup();delete s.env.LUNA_COMPARISON;await s.run();expect(s.fetcher).not.toHaveBeenCalled();s.env.LUNA_COMPARISON='enabled';s.env.PROVIDER_GENERATION_DEVICES='not-this-device';await s.run();expect(s.fetcher).not.toHaveBeenCalled();delete s.env.PROVIDER_GENERATION_DEVICES;s.global.providerEnabled.mockResolvedValue(false);await s.run();expect(s.device.reserve).not.toHaveBeenCalled();
    expect(eligible(s.env,s.auth,LUNA_POLICY,JEV_MODEL)).toBe(false);
  });
  it('global cap refusal prevents the paid call',async()=>{const s=setup();s.global.reserveGlobal.mockResolvedValue({ok:false});expect((await s.run()).provenance?.fallbackReason).toBe('SPEND_CAP');expect(s.calls).not.toContain('provider');});
  it('invalid output still reconciles billed usage',async()=>{const s=setup();s.fetcher.mockImplementationOnce(async()=>Response.json({data:{id:LUNA_MODEL,endpoints:[endpoint]}})).mockImplementationOnce(async()=>{const a=answer();a.choices[0].message.content='{"choice":"invented"}';return Response.json(a);});expect((await s.run()).provenance?.fallbackReason).toBe('INVALID_OUTPUT');expect(s.global.reconcile).toHaveBeenCalled();});
  it('keeps unknown holds after transport failure and never retries',async()=>{const s=setup();s.fetcher.mockImplementationOnce(async()=>Response.json({data:{id:LUNA_MODEL,endpoints:[endpoint]}})).mockRejectedValueOnce(new Error('PRIVATE'));await s.run();expect(s.fetcher).toHaveBeenCalledTimes(2);expect(s.global.markUnknown).toHaveBeenCalled();});
  it('sends only allowlisted data with bounded structured output',async()=>{const price=await fetchLunaPrice(setup().fetcher);const body=lunaRequestBody(candidates,{...context,freeTextNote:'PRIVATE NOTE'},price);expect(body).not.toContain('PRIVATE');const b=JSON.parse(body);expect(b.provider).toMatchObject({only:['openai'],data_collection:'deny',allow_fallbacks:false,require_parameters:true});expect(b.max_tokens).toBe(1024);expect(b.response_format.json_schema.schema.properties.choice.enum).toEqual(['a','b']);expect(costBound(price)).toBeGreaterThan(0.005);});
  it.each(['length','tool_calls','content_filter'])('rejects incomplete answers %s',finish=>{const a=answer();a.choices[0].finish_reason=finish;expect(()=>validateLuna(a,candidates)).toThrow('INVALID_OUTPUT');});
  it.each(['bad json','{"choice":"invented"}','{"choice":"a","extra":true}'])('rejects invalid choice %s',content=>{const a=answer();a.choices[0].message.content=content;expect(()=>validateLuna(a,candidates)).toThrow();});
  it('rejects other models, refusals, and invalid usage',()=>{const a=answer();a.model=JEV_MODEL;expect(()=>validateLuna(a,candidates)).toThrow();const b=answer();Object.assign(b.choices[0].message,{refusal:'PRIVATE'});expect(()=>validateLuna(b,candidates)).toThrow();const c=answer();c.usage.completion_tokens=1025;expect(()=>validateLuna(c,candidates)).toThrow();});
  it.each([undefined,'oops','-1'])('fails closed on missing or invalid price %s',completion=>expect(fetchLunaPrice(async()=>Response.json({data:{id:LUNA_MODEL,endpoints:[{...endpoint,pricing:{prompt:'0.0000002',completion}}]}}))).rejects.toThrow());
});

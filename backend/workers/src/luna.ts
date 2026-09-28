import policy from '../../../shared/privacy-policy-version.json';
import { boundedJSON, object, safeGarment, safeContext, JEV_INSTRUCTION, MAX_REQUEST_BYTES, DecisionValidationError, type Candidate, type Price } from './jev.js';
import type { ContextSnapshot } from '@personal-stylist/outfit-engine';

export const LUNA_MODEL = 'openai/gpt-5.6-luna';
export const LUNA_POLICY = policy.lunaPolicyVersion;
export const LUNA_PROMPT_VERSION = 'outfit-choice-luna-v1';
const MAX_OUTPUT = 1024;
// Conservative byte bound for the bounded ASCII request plus protocol overhead.
const MAX_INPUT = MAX_REQUEST_BYTES + 4096;

export async function fetchLunaPrice(fetcher: typeof fetch): Promise<Price> {
  const response = await fetcher(`https://openrouter.ai/api/v1/models/${LUNA_MODEL}/endpoints`, { signal: AbortSignal.timeout(1500) });
  if (!response.ok) throw new Error('MODEL_UNAVAILABLE');
  const listing = object(object(await boundedJSON(response)).data);
  if (listing.id !== LUNA_MODEL || !Array.isArray(listing.endpoints)) throw new Error('MODEL_UNAVAILABLE');
  const endpoint = listing.endpoints.map(object).find(e => e.tag === 'openai' && e.status === 0);
  const parameters = endpoint?.supported_parameters;
  if (!endpoint || typeof endpoint.context_length !== 'number' || endpoint.context_length < MAX_INPUT + MAX_OUTPUT ||
      typeof endpoint.max_completion_tokens !== 'number' || endpoint.max_completion_tokens < MAX_OUTPUT ||
      !Array.isArray(parameters) || !['structured_outputs', 'response_format', 'max_tokens', 'reasoning'].every(p => parameters.includes(p))) throw new Error('MODEL_UNAVAILABLE');
  const pricing = object(endpoint.pricing);
  const parse = (v: unknown) => typeof v === 'string' && /^\d+(\.\d+)?$/.test(v) ? Number(v) : typeof v === 'number' ? v : NaN;
  const prompt = parse(pricing.prompt), completion = parse(pricing.completion);
  if (![prompt, completion].every(n => Number.isFinite(n) && n >= 0)) throw new Error('MODEL_UNPRICED');
  // Refuse pricing tiers inside our bound; do not accidentally under-reserve.
  if (Array.isArray(pricing.overrides) && pricing.overrides.some(v => {
    const threshold = object(v).min_prompt_tokens;
    return typeof threshold !== 'number' || threshold <= MAX_INPUT;
  })) throw new Error('MODEL_UNPRICED');
  return { prompt, completion, context: MAX_INPUT, maxOutput: MAX_OUTPUT };
}

export function lunaRequestBody<T>(candidates: Candidate<T>[], context: ContextSnapshot, price: Price): string {
  const body = JSON.stringify({ model: LUNA_MODEL,
    messages: [{ role: 'system', content: JEV_INSTRUCTION }, { role: 'user', content: JSON.stringify({
      context: safeContext(context), candidates: Object.fromEntries(candidates.map(c => [c.token, { garments: c.garments.map(safeGarment) }]))
    }) }],
    response_format: { type: 'json_schema', json_schema: { name: 'outfit_choice', strict: true,
      schema: { type: 'object', properties: { choice: { type: 'string', enum: candidates.map(c => c.token) } }, required: ['choice'], additionalProperties: false } } },
    max_tokens: MAX_OUTPUT, reasoning: { effort: 'low', exclude: true },
    provider: { only: ['openai'], data_collection: 'deny', allow_fallbacks: false, require_parameters: true,
      max_price: { prompt: price.prompt * 1e6, completion: price.completion * 1e6 } }
  });
  if (new TextEncoder().encode(body).length > MAX_REQUEST_BYTES) throw new Error('REQUEST_TOO_LARGE');
  return body;
}

export function validateLuna<T>(raw: unknown, candidates: Candidate<T>[]) {
  const r = object(raw), usage = object(r.usage);
  const reject = (reason: ConstructorParameters<typeof DecisionValidationError>[0]): never => { throw new DecisionValidationError(reason); };
  if (r.model !== LUNA_MODEL && !(typeof r.model === 'string' && /^openai\/gpt-5\.6-luna-\d{8}$/.test(r.model))) reject('MODEL_MISMATCH');
  if (!Array.isArray(r.choices) || r.choices.length !== 1) return reject('ANSWER_SHAPE');
  const row = object(r.choices[0]), message = object(row.message);
  if (row.finish_reason !== 'stop' || message.refusal || message.tool_calls || typeof message.content !== 'string') return reject('ANSWER_SHAPE');
  let answer: Record<string, unknown>;
  try { answer = object(JSON.parse(message.content)); } catch { return reject('ANSWER_SHAPE'); }
  if (Object.keys(answer).join() !== 'choice') reject('ANSWER_SHAPE');
  const candidate = candidates.find(c => c.token === answer.choice);
  if (!candidate) return reject('UNKNOWN_CHOICE');
  if (![usage.prompt_tokens, usage.completion_tokens].every(n => typeof n === 'number' && Number.isSafeInteger(n) && n >= 0) ||
      (usage.prompt_tokens as number) > MAX_INPUT || (usage.completion_tokens as number) > MAX_OUTPUT) reject('INVALID_USAGE');
  return { result: candidate.result, model: r.model as string, inputTokens: usage.prompt_tokens, outputTokens: usage.completion_tokens };
}

import policy from '../../../shared/privacy-policy-version.json';
import { DEFAULT_REQUIRE_SLOTS, generateLocal, isLocalProblem, type LocalGenerateRequest, type LocalGenerateResponse,
  type AlternativesRequest, type AlternativesResponse, type GarmentSummary, type ContextSnapshot } from '@personal-stylist/outfit-engine';
import { createHash } from 'node:crypto';

export const JEV_MODEL = 'typesafe/jev-1.13';
export const JEV_PROMPT_VERSION = 'outfit-choice-v1';
export const JEV_INSTRUCTION = 'Choose the outfit that best matches the occasion and temperature, with coordinated color families and compatible formality. Choose only one offered complete candidate. All candidates already satisfy the application constraints. Return a typed choice only.';
export const POLICY_VERSION = policy.policyVersion;
export const MAX_REQUEST_BYTES = 24_000;
export const MIN_CONFIDENCE = 0.5;
export type Candidate<T> = { token: string; result: T; garments: GarmentSummary[] };
const COLORS = new Set('white cream grey charcoal black navy blue light_blue olive green brown tan burgundy red orange yellow purple pink multi'.split(' '));
const SLOTS = new Set('TOP BOTTOM FOOTWEAR MID_LAYER JACKET OUTERWEAR ACCESSORY'.split(' '));
const OCCASIONS = new Set('WORK_STANDARD WORK_IMPORTANT CLIENT_EXEC CASUAL_DAY EVENING_OUT TRAVEL_DAY WEEKEND_ERRANDS SPECIAL_EVENT'.split(' '));
const TEMPERATURES = new Set('COLD COOL MILD WARM HOT'.split(' '));
const TIMES = new Set('MORNING AFTERNOON EVENING'.split(' '));
function degree(n: unknown): number | undefined { return typeof n === 'number' && Number.isInteger(n) && n >= 1 && n <= 5 ? n : undefined; }

/** Construct from allowlists; never serialize client objects or identifiers. */
export function safeGarment(g: GarmentSummary) {
  return {
    slot: SLOTS.has(g.slot) ? g.slot : undefined,
    colorPrimary: g.colorPrimary && COLORS.has(g.colorPrimary.family) ? { family: g.colorPrimary.family } : undefined,
    colorSecondary: g.colorSecondary && COLORS.has(g.colorSecondary.family) ? { family: g.colorSecondary.family } : undefined,
    formality: degree(g.formality), warmth: degree(g.warmth),
  };
}
function safeContext(c: ContextSnapshot) {
  return { occasion: OCCASIONS.has(c.occasion) ? c.occasion : undefined,
    occasionFormality: degree(c.occasionFormality),
    temperatureBand: TEMPERATURES.has(c.temperatureBand) ? c.temperatureBand : undefined,
    precipitation: typeof c.precipitation === 'boolean' ? c.precipitation : undefined,
    timeOfDay: c.timeOfDay && TIMES.has(c.timeOfDay) ? c.timeOfDay : undefined };
}
function token(): string { return 'o_' + crypto.randomUUID().replaceAll('-', '').slice(0, 12); }
export function generateCandidates(request: LocalGenerateRequest, first: LocalGenerateResponse): Candidate<LocalGenerateResponse>[] {
  const candidates: Candidate<LocalGenerateResponse>[] = [];
  const tokens = new Set<string>();
  const excluded = [...(request.options?.excludeGarmentSets ?? [])];
  let next = first;
  const seen = new Set<string>();
  for (let i = 0; i < 4; i++) {
    const ids = next.assignments.flatMap(a => a.garmentId ? [a.garmentId] : []);
    const key = [...ids].sort().join(',');
    if (seen.has(key) || ids.length === 0) break;
    seen.add(key);
    let keyToken = token();
    while (tokens.has(keyToken)) keyToken = token();
    tokens.add(keyToken);
    const required = request.options?.requireSlots ?? DEFAULT_REQUIRE_SLOTS;
    const complete = required.every(slot => next.assignments.some(a => a.slot === slot && a.garmentId))
      && !next.assignments.some(a => !a.garmentId && a.gapReason);
    if (complete) candidates.push({ token: keyToken, result: next, garments: ids.map(id => request.wardrobe.find(g => g.id === id)!).filter(Boolean) });
    excluded.push(ids);
    const generated = generateLocal({ ...request, options: { ...request.options, excludeGarmentSets: excluded } });
    if (isLocalProblem(generated)) break;
    next = generated;
  }
  return candidates;
}
export function swapCandidates(request: AlternativesRequest, result: AlternativesResponse): Candidate<AlternativesResponse>[] {
  const tokens = new Set<string>();
  return result.alternatives.slice(0, 8).flatMap(row => {
    let keyToken = token();
    while (tokens.has(keyToken)) keyToken = token();
    tokens.add(keyToken);
    const replacedSlots = new Set([request.slot, ...(row.setPartnerIds ?? []).map(id => request.wardrobe.find(g => g.id === id)?.slot)]);
    const ids = [row.garmentId, ...(row.setPartnerIds ?? []), ...request.currentAssignments.filter(a => !replacedSlots.has(a.slot)).flatMap(a => a.garmentId ? [a.garmentId] : [])];
    const garments = [...new Set(ids)].map(id => request.wardrobe.find(g => g.id === id)!).filter(Boolean);
    if (!DEFAULT_REQUIRE_SLOTS.every(slot => garments.some(g => g.slot === slot))) return [];
    if (request.currentAssignments.some(a => !replacedSlots.has(a.slot) && !a.garmentId && a.gapReason)) return [];
    return [{ token: keyToken, result: { ...result, alternatives: [row, ...result.alternatives.filter(r => r !== row)] }, garments }];
  });
}
export interface Price { prompt: number; completion: number; context: number; maxOutput: number }
export function costBound(price: Price): number {
  return Math.ceil((price.prompt * price.context + price.completion * price.maxOutput) * 1e6) / 1e6;
}
export function requestBody<T>(candidates: Candidate<T>[], context: ContextSnapshot, price: Price) {
  const criteria = Object.fromEntries(candidates.map(c => [c.token, { garments: c.garments.map(safeGarment) }]));
  const body = { model: JEV_MODEL, state: { context: safeContext(context) },
    questions: { outfit: { type: 'choice', instructions: JEV_INSTRUCTION, criteria } },
    provider: { only: ['typesafe'], data_collection: 'deny', allow_fallbacks: false,
      require_parameters: true, max_price: { prompt: price.prompt * 1e6, completion: price.completion * 1e6 } } };
  const serialized = JSON.stringify(body);
  if (new TextEncoder().encode(serialized).length > MAX_REQUEST_BYTES) throw new Error('REQUEST_TOO_LARGE');
  return serialized;
}
export async function boundedJSON(response: Response, limit = 128_000): Promise<unknown> {
  const reader = response.body?.getReader();
  if (!reader) throw new Error('EMPTY_RESPONSE');
  const chunks: Uint8Array[] = []; let size = 0;
  try {
    while (true) {
      const part = await reader.read(); if (part.done) break;
      size += part.value.length;
      if (size > limit) throw new Error('RESPONSE_TOO_LARGE');
      chunks.push(part.value);
    }
  } finally { await reader.cancel().catch(() => {}); }
  const bytes = new Uint8Array(size); let offset = 0;
  for (const c of chunks) { bytes.set(c, offset); offset += c.length; }
  return JSON.parse(new TextDecoder().decode(bytes));
}
export function object(v: unknown): Record<string, unknown> { return v !== null && typeof v === 'object' && !Array.isArray(v) ? v as Record<string, unknown> : {}; }
export async function fetchPrice(fetcher: typeof fetch = fetch): Promise<Price> {
  const response = await fetcher('https://openrouter.ai/api/v1/models/typesafe/jev-1.13/endpoints', { signal: AbortSignal.timeout(1500) });
  if (!response.ok) throw new Error('MODEL_UNAVAILABLE');
  const listing = object(object(await boundedJSON(response)).data);
  if (listing.id !== JEV_MODEL || !Array.isArray(listing.endpoints)) throw new Error('MODEL_UNAVAILABLE');
  const endpoint = listing.endpoints.map(object).find(e => e.tag === 'typesafe' && e.status === 0);
  if (!endpoint || endpoint.context_length !== 32000) throw new Error('MODEL_UNAVAILABLE');
  const pricing = object(endpoint.pricing);
  const parse = (v: unknown) => typeof v === 'string' && /^\d+(\.\d+)?$/.test(v) ? Number(v) : typeof v === 'number' ? v : NaN;
  const prompt = parse(pricing.prompt), completion = parse(pricing.completion);
  const maxOutput = endpoint.max_completion_tokens;
  if (![prompt, completion].every(n => Number.isFinite(n) && n >= 0) || typeof maxOutput !== 'number' || !Number.isSafeInteger(maxOutput) || maxOutput < 0 || maxOutput > 32000) throw new Error('MODEL_UNPRICED');
  return { prompt, completion, context: 32000, maxOutput };
}
export type DecisionRejection = 'MODEL_MISMATCH' | 'ANSWER_SHAPE' | 'UNKNOWN_CHOICE' |
  'INVALID_CONFIDENCE' | 'LOW_CONFIDENCE' | 'INVALID_PROBABILITIES' | 'INVALID_USAGE';
/** Fixed diagnostic codes only; never retain provider content in an error. */
export class DecisionValidationError extends Error {
  constructor(readonly reason: DecisionRejection) { super('INVALID_OUTPUT'); }
}
export function validateDecision<T>(raw: unknown, candidates: Candidate<T>[]) {
  const response = object(raw), answers = object(response.answers), answer = object(answers.outfit), usage = object(response.usage);
  const validModel = response.model === JEV_MODEL || (typeof response.model === 'string' && /^typesafe\/jev-1\.13-\d{8}$/.test(response.model));
  const reject = (reason: DecisionRejection): never => { throw new DecisionValidationError(reason); };
  if (!validModel) reject('MODEL_MISMATCH');
  if (Object.keys(answers).join() !== 'outfit' || answer.type !== 'choice') reject('ANSWER_SHAPE');
  const candidate = candidates.find(c => c.token === answer.choice);
  if (!candidate) return reject('UNKNOWN_CHOICE');
  if (typeof answer.confidence !== 'number' || !Number.isFinite(answer.confidence) || answer.confidence < 0 || answer.confidence > 1) reject('INVALID_CONFIDENCE');
  if ((answer.confidence as number) < MIN_CONFIDENCE) reject('LOW_CONFIDENCE');
  const probabilities = object(answer.probabilities);
  const probs = Object.values(probabilities);
  if (Object.keys(probabilities).length !== candidates.length || !candidates.every(c => Object.hasOwn(probabilities, c.token)) ||
    !probs.every(p => typeof p === 'number' && Number.isFinite(p) && p >= 0 && p <= 1) ||
    Math.abs((probs as number[]).reduce((a, b) => a + b, 0) - 1) > 0.02) reject('INVALID_PROBABILITIES');
  if (![usage.input_tokens, usage.output_tokens].every(n => typeof n === 'number' && Number.isSafeInteger(n) && n >= 0)) reject('INVALID_USAGE');
  return { result: candidate.result, model: response.model as string, inputTokens: usage.input_tokens, outputTokens: usage.output_tokens };
}
export const promptHash = createHash('sha256').update(JEV_INSTRUCTION).digest('hex');

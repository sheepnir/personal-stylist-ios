import { answersObjectHasDuplicateKeys } from "./parseDecisionsDuplicateKeys.js";
import { MAX_PROVIDER_RESPONSE_BYTES } from "./constants.js";
import { createOwnRecord, ownHas } from "./safeOwn.js";
import type {
  DecisionsAnswer,
  DecisionsUsage,
  ParsedDecisionsResponse,
} from "./types.js";

function isPlainJsonRecord(v: unknown): v is Record<string, unknown> {
  if (typeof v !== "object" || v === null || Array.isArray(v)) return false;
  const proto = Object.getPrototypeOf(v);
  return proto === null || proto === Object.prototype;
}

function parseUsage(raw: unknown): DecisionsUsage | null {
  if (!isPlainJsonRecord(raw)) return null;
  if (!ownHas(raw, "input_tokens") || !ownHas(raw, "output_tokens")) {
    return null;
  }
  const input = raw.input_tokens;
  const output = raw.output_tokens;
  if (
    typeof input !== "number" ||
    typeof output !== "number" ||
    !Number.isInteger(input) ||
    !Number.isInteger(output) ||
    input < 0 ||
    output < 0
  ) {
    return null;
  }
  return { input_tokens: input, output_tokens: output };
}

function parseAnswerShape(raw: unknown): DecisionsAnswer | null {
  if (!isPlainJsonRecord(raw)) return null;
  if (!ownHas(raw, "type")) return null;
  const typeVal = raw.type;
  if (typeof typeVal !== "string") return null;
  if (typeVal === "choice") {
    if (!ownHas(raw, "choice")) return null;
    const choice = raw.choice;
    if (typeof choice !== "string") return null;
    return { type: "choice", choice };
  }
  if (typeVal === "noul") {
    if (!ownHas(raw, "noul")) return null;
    const noul = raw.noul;
    if (typeof noul !== "number" || !Number.isFinite(noul)) return null;
    return { type: "noul", noul };
  }
  return null;
}

function buildAnswersMap(
  rawAnswers: Record<string, unknown>,
): Record<string, DecisionsAnswer> | null {
  if (!isPlainJsonRecord(rawAnswers)) return null;
  const answers = createOwnRecord<DecisionsAnswer>();
  for (const key of Object.keys(rawAnswers)) {
    if (!ownHas(rawAnswers, key)) continue;
    const parsed = parseAnswerShape(rawAnswers[key]);
    if (!parsed) return null;
    answers[key] = parsed;
  }
  return answers;
}

export type ParseDecisionsBodyResult =
  | { ok: true; value: ParsedDecisionsResponse }
  | { ok: false; cause: "OUTPUT_PARSE" | "OUTPUT_SCHEMA" };

function utf8ByteLength(body: string): number {
  return new TextEncoder().encode(body).length;
}

export function parseDecisionsResponseBody(
  body: string,
): ParseDecisionsBodyResult {
  if (utf8ByteLength(body) > MAX_PROVIDER_RESPONSE_BYTES) {
    return { ok: false, cause: "OUTPUT_PARSE" };
  }
  if (answersObjectHasDuplicateKeys(body)) {
    return { ok: false, cause: "OUTPUT_PARSE" };
  }
  let json: unknown;
  try {
    json = JSON.parse(body);
  } catch {
    return { ok: false, cause: "OUTPUT_PARSE" };
  }
  if (!isPlainJsonRecord(json)) return { ok: false, cause: "OUTPUT_PARSE" };
  if (!ownHas(json, "model")) return { ok: false, cause: "OUTPUT_PARSE" };
  const model = json.model;
  if (typeof model !== "string") return { ok: false, cause: "OUTPUT_PARSE" };
  if (!ownHas(json, "usage")) {
    return { ok: false, cause: "OUTPUT_PARSE" };
  }
  const usage = parseUsage(json.usage);
  if (!usage) return { ok: false, cause: "OUTPUT_PARSE" };
  if (!ownHas(json, "answers")) {
    return { ok: false, cause: "OUTPUT_PARSE" };
  }
  const rawAnswers = json.answers;
  if (!isPlainJsonRecord(rawAnswers)) {
    return { ok: false, cause: "OUTPUT_PARSE" };
  }

  const answers = buildAnswersMap(rawAnswers);
  if (!answers) {
    return { ok: false, cause: "OUTPUT_SCHEMA" };
  }

  return {
    ok: true,
    value: {
      model,
      usage,
      answers,
    },
  };
}

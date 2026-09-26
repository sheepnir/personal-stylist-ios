import { answersObjectHasDuplicateKeys } from "./parseDecisionsDuplicateKeys.js";
import { MAX_PROVIDER_RESPONSE_BYTES } from "./constants.js";
import { createOwnRecord, ownHas, ownKeys } from "./safeOwn.js";
import type {
  DecisionsAnswer,
  DecisionsUsage,
  ParsedDecisionsResponse,
  ProviderQuestion,
  ProviderSetToken,
} from "./types.js";
import type { Slot } from "../types.js";

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

function parseUsage(raw: unknown): DecisionsUsage | null {
  if (!isRecord(raw)) return null;
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
  if (!isRecord(raw)) return null;
  if (typeof raw.type !== "string") return null;
  if (raw.type === "choice") {
    if (typeof raw.choice !== "string") return null;
    return { type: "choice", choice: raw.choice };
  }
  if (raw.type === "noul") {
    if (typeof raw.noul !== "number" || Number.isNaN(raw.noul)) return null;
    return { type: "noul", noul: raw.noul };
  }
  return null;
}

function buildAnswersMap(
  rawAnswers: Record<string, unknown>,
): Record<string, DecisionsAnswer> | null {
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
  if (!isRecord(json)) return { ok: false, cause: "OUTPUT_PARSE" };
  if (typeof json.model !== "string") {
    return { ok: false, cause: "OUTPUT_PARSE" };
  }
  const usage = parseUsage(json.usage);
  if (!usage) return { ok: false, cause: "OUTPUT_PARSE" };
  if (!isRecord(json.answers)) {
    return { ok: false, cause: "OUTPUT_PARSE" };
  }

  const answers = buildAnswersMap(json.answers);
  if (!answers) {
    return { ok: false, cause: "OUTPUT_SCHEMA" };
  }

  return {
    ok: true,
    value: {
      model: json.model,
      usage,
      answers,
    },
  };
}

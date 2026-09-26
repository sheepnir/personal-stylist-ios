import { answersObjectHasDuplicateKeys } from "./parseDecisionsDuplicateKeys.js";
import { MAX_PROVIDER_RESPONSE_BYTES } from "./constants.js";
import {
  createOwnRecord,
  isReservedMapKey,
  ownHas,
  ownKeys,
} from "./safeOwn.js";
import type {
  DecisionsAnswer,
  DecisionsUsage,
  ParsedDecisionsResponse,
  ProviderQuestion,
  ProviderSetToken,
} from "./types.js";
import type { Slot } from "../types.js";

function isPlainJsonRecord(v: unknown): v is Record<string, unknown> {
  if (typeof v !== "object" || v === null || Array.isArray(v)) return false;
  const proto = Object.getPrototypeOf(v);
  return proto === null || proto === Object.prototype;
}

const MAX_USAGE_TOKEN_COUNT = 10_000_000;

type ParseUsageResult =
  | { ok: true; value: DecisionsUsage }
  | { ok: false; cause: "OUTPUT_PARSE" | "OUTPUT_SCHEMA" };

function asSafeUsageTokenCount(n: unknown): number | null {
  if (
    typeof n === "number" &&
    Number.isSafeInteger(n) &&
    n >= 0 &&
    n <= MAX_USAGE_TOKEN_COUNT
  ) {
    return n;
  }
  return null;
}

function parseUsage(raw: unknown): ParseUsageResult {
  if (!isPlainJsonRecord(raw)) {
    return { ok: false, cause: "OUTPUT_PARSE" };
  }
  if (!ownHas(raw, "input_tokens") || !ownHas(raw, "output_tokens")) {
    return { ok: false, cause: "OUTPUT_PARSE" };
  }
  const input = asSafeUsageTokenCount(raw.input_tokens);
  const output = asSafeUsageTokenCount(raw.output_tokens);
  if (input === null || output === null) {
    return { ok: false, cause: "OUTPUT_SCHEMA" };
  }
  return {
    ok: true,
    value: { input_tokens: input, output_tokens: output },
  };
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
    if (noul < 0 || noul > 1) return null;
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
    if (isReservedMapKey(key)) return null;
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
  const usageResult = parseUsage(json.usage);
  if (!usageResult.ok) {
    return { ok: false, cause: usageResult.cause };
  }
  const usage = usageResult.value;
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

export function validateDecisionsAnswersAgainstQuestions(
  answers: Record<string, DecisionsAnswer>,
  questions: ProviderQuestion[],
): boolean {
  const questionIdList = questions.map((q) => q.id);
  const questionIds = new Set(questionIdList);
  if (questionIds.size !== questionIdList.length) {
    return false;
  }

  const answerKeys = ownKeys(answers);
  if (answerKeys.length !== questionIds.size) return false;
  for (const id of questionIds) {
    if (!ownHas(answers, id)) return false;
  }
  for (const key of answerKeys) {
    if (!questionIds.has(key)) return false;
  }

  for (const q of questions) {
    const answer = answers[q.id];
    if (!answer) return false;
    if (q.type === "choice") {
      if (answer.type !== "choice") return false;
      if (!ownHas(q.options, answer.choice)) return false;
    } else if (q.type === "noul") {
      if (answer.type !== "noul") return false;
      if (
        !Number.isFinite(answer.noul) ||
        answer.noul < 0 ||
        answer.noul > 1
      ) {
        return false;
      }
    }
  }
  return true;
}

export function validateProviderChoiceAnswers(params: {
  answers: Record<string, DecisionsAnswer>;
  questions: ProviderQuestion[];
  requiredSlots: Set<Slot>;
  setTokens?: ProviderSetToken[];
}): boolean {
  const { answers, questions, requiredSlots, setTokens = [] } = params;
  const setByToken = new Map(setTokens.map((s) => [s.token, s]));

  for (const q of questions) {
    if (q.type !== "choice") continue;
    const answer = answers[q.id];
    if (!answer || answer.type !== "choice") continue;
    const choice = answer.choice;

    if (choice === "none") {
      if (requiredSlots.has(q.slot)) return false;
      if (!ownHas(q.options, "none")) return false;
      continue;
    }

    if (choice.startsWith("s_")) {
      const setInfo = setByToken.get(choice);
      if (!setInfo) return false;
      if (q.slot !== setInfo.firstSlot) return false;
      if (setInfo.memberGarmentIds.length === 0) return false;
      if (!ownHas(q.options, choice)) return false;
      continue;
    }

    if (!ownHas(q.options, choice)) return false;
  }

  for (const q of questions) {
    if (q.type !== "choice") continue;
    if (requiredSlots.has(q.slot) && ownHas(q.options, "none")) {
      return false;
    }
  }

  return true;
}

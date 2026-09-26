import type {
  DecisionsAnswer,
  DecisionsUsage,
  ParsedDecisionsResponse,
  ProviderQuestion,
} from "./types.js";

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

function parseAnswer(raw: unknown): DecisionsAnswer | null {
  if (!isRecord(raw) || typeof raw.type !== "string") return null;
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

export function parseDecisionsResponseBody(
  body: string,
): ParsedDecisionsResponse | null {
  let json: unknown;
  try {
    json = JSON.parse(body);
  } catch {
    return null;
  }
  if (!isRecord(json)) return null;
  if (typeof json.model !== "string") return null;
  const usage = parseUsage(json.usage);
  if (!usage) return null;
  if (!isRecord(json.answers)) return null;

  const answers: Record<string, DecisionsAnswer> = {};
  for (const [id, raw] of Object.entries(json.answers)) {
    const parsed = parseAnswer(raw);
    if (!parsed) return null;
    answers[id] = parsed;
  }

  return {
    model: json.model,
    usage,
    answers,
  };
}

export function validateDecisionsAnswersAgainstQuestions(
  answers: Record<string, DecisionsAnswer>,
  questions: ProviderQuestion[],
): boolean {
  const questionIds = new Set(questions.map((q) => q.id));
  const answerIds = new Set(Object.keys(answers));
  if (questionIds.size !== answerIds.size) return false;
  for (const id of questionIds) {
    if (!answerIds.has(id)) return false;
  }

  for (const q of questions) {
    const answer = answers[q.id];
    if (!answer) return false;
    if (q.type === "choice") {
      if (answer.type !== "choice") return false;
      if (!(answer.choice in q.options)) return false;
    } else if (q.type === "noul") {
      if (answer.type !== "noul") return false;
      if (answer.noul < 0 || answer.noul > 1) return false;
    }
  }
  return true;
}

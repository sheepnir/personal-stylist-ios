/**
 * Detect duplicate keys in the raw `answers` object of a Decisions response.
 * `JSON.parse` silently keeps the last duplicate key; provider output must fail closed.
 */

function skipWhitespace(s: string, i: number): number {
  while (i < s.length && /\s/.test(s[i]!)) i++;
  return i;
}

function readJsonString(s: string, i: number): { value: string; end: number } | null {
  if (s[i] !== '"') return null;
  let out = "";
  i++;
  while (i < s.length) {
    const ch = s[i]!;
    if (ch === '"') return { value: out, end: i + 1 };
    if (ch === "\\") {
      i++;
      if (i >= s.length) return null;
      out += s[i]!;
      i++;
      continue;
    }
    out += ch;
    i++;
  }
  return null;
}

/**
 * Collect keys at depth 1 inside the `answers` object (direct answer ids only).
 */
function collectAnswersObjectKeys(body: string, openBrace: number): string[] | null {
  if (body[openBrace] !== "{") return null;
  let depth = 0;
  const keys: string[] = [];
  for (let i = openBrace; i < body.length; i++) {
    const ch = body[i]!;
    if (ch === '"') {
      const str = readJsonString(body, i);
      if (!str) return null;
      if (depth === 1) {
        let j = skipWhitespace(body, str.end);
        if (body[j] === ":") {
          keys.push(str.value);
        }
      }
      i = str.end - 1;
      continue;
    }
    if (ch === "{") {
      depth++;
      continue;
    }
    if (ch === "}") {
      depth--;
      if (depth === 0) break;
      continue;
    }
  }
  return keys;
}

export function answersObjectHasDuplicateKeys(body: string): boolean {
  const match = /"answers"\s*:\s*\{/.exec(body);
  if (!match) return false;
  const start = match.index + match[0].length - 1;
  const keys = collectAnswersObjectKeys(body, start);
  if (!keys) return false;
  const seen = new Set<string>();
  for (const k of keys) {
    if (seen.has(k)) return true;
    seen.add(k);
  }
  return false;
}

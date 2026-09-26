/**
 * Detect duplicate object keys in raw Decisions JSON before `JSON.parse`.
 * `JSON.parse` silently keeps the last duplicate key; provider output must fail closed.
 */

/** Max nesting depth while scanning (fail closed beyond this). */
export const MAX_JSON_DUPLICATE_SCAN_DEPTH = 64;

function skipWhitespace(s: string, i: number): number {
  while (i < s.length && /\s/.test(s[i]!)) i++;
  return i;
}

function readJsonStringDecoded(
  s: string,
  i: number,
): { value: string; end: number } | null {
  if (s[i] !== '"') return null;
  let out = "";
  i++;
  while (i < s.length) {
    const ch = s[i]!;
    if (ch === '"') return { value: out, end: i + 1 };
    if (ch === "\\") {
      i++;
      if (i >= s.length) return null;
      const esc = s[i]!;
      switch (esc) {
        case '"':
        case "\\":
        case "/":
          out += esc;
          i++;
          break;
        case "b":
          out += "\b";
          i++;
          break;
        case "f":
          out += "\f";
          i++;
          break;
        case "n":
          out += "\n";
          i++;
          break;
        case "r":
          out += "\r";
          i++;
          break;
        case "t":
          out += "\t";
          i++;
          break;
        case "u": {
          if (i + 5 > s.length) return null;
          const hex = s.slice(i + 1, i + 5);
          if (!/^[0-9a-fA-F]{4}$/.test(hex)) return null;
          out += String.fromCodePoint(parseInt(hex, 16));
          i += 5;
          break;
        }
        default:
          return null;
      }
      continue;
    }
    out += ch;
    i++;
  }
  return null;
}

type ScanStatus = "ok" | "duplicate" | "invalid";

function scanValue(s: string, i: number, depth: number): [ScanStatus, number] {
  if (depth > MAX_JSON_DUPLICATE_SCAN_DEPTH) {
    return ["invalid", i];
  }
  i = skipWhitespace(s, i);
  if (i >= s.length) return ["invalid", i];

  const ch = s[i]!;
  if (ch === '"') {
    const str = readJsonStringDecoded(s, i);
    return str ? ["ok", str.end] : ["invalid", i];
  }
  if (ch === "{") return scanObject(s, i, depth);
  if (ch === "[") return scanArray(s, i, depth);
  if (ch === "t" && s.startsWith("true", i)) return ["ok", i + 4];
  if (ch === "f" && s.startsWith("false", i)) return ["ok", i + 5];
  if (ch === "n" && s.startsWith("null", i)) return ["ok", i + 4];
  if (ch === "-" || (ch >= "0" && ch <= "9")) {
    return scanNumber(s, i);
  }
  return ["invalid", i];
}

function scanNumber(s: string, i: number): [ScanStatus, number] {
  let j = i;
  if (s[j] === "-") j++;
  if (j >= s.length) return ["invalid", i];
  if (s[j] === "0") {
    j++;
  } else if (s[j]! >= "1" && s[j]! <= "9") {
    while (j < s.length && s[j]! >= "0" && s[j]! <= "9") j++;
  } else {
    return ["invalid", i];
  }
  if (j < s.length && s[j] === ".") {
    j++;
    if (j >= s.length || s[j]! < "0" || s[j]! > "9") return ["invalid", i];
    while (j < s.length && s[j]! >= "0" && s[j]! <= "9") j++;
  }
  if (j < s.length && (s[j] === "e" || s[j] === "E")) {
    j++;
    if (j < s.length && (s[j] === "+" || s[j] === "-")) j++;
    if (j >= s.length || s[j]! < "0" || s[j]! > "9") return ["invalid", i];
    while (j < s.length && s[j]! >= "0" && s[j]! <= "9") j++;
  }
  return ["ok", j];
}

function scanObject(s: string, i: number, depth: number): [ScanStatus, number] {
  if (s[i] !== "{") return ["invalid", i];
  const seen = new Set<string>();
  i++;
  i = skipWhitespace(s, i);
  if (i < s.length && s[i] === "}") return ["ok", i + 1];

  while (i < s.length) {
    i = skipWhitespace(s, i);
    const key = readJsonStringDecoded(s, i);
    if (!key) return ["invalid", i];
    if (seen.has(key.value)) return ["duplicate", key.end];
    seen.add(key.value);

    i = skipWhitespace(s, key.end);
    if (s[i] !== ":") return ["invalid", i];
    i++;

    const [childStatus, afterChild] = scanValue(s, i, depth + 1);
    if (childStatus !== "ok") return [childStatus, afterChild];
    i = skipWhitespace(s, afterChild);

    if (i < s.length && s[i] === "}") return ["ok", i + 1];
    if (s[i] !== ",") return ["invalid", i];
    i++;
  }
  return ["invalid", i];
}

function scanArray(s: string, i: number, depth: number): [ScanStatus, number] {
  if (s[i] !== "[") return ["invalid", i];
  i++;
  i = skipWhitespace(s, i);
  if (i < s.length && s[i] === "]") return ["ok", i + 1];

  while (i < s.length) {
    const [childStatus, afterChild] = scanValue(s, i, depth + 1);
    if (childStatus !== "ok") return [childStatus, afterChild];
    i = skipWhitespace(s, afterChild);

    if (i < s.length && s[i] === "]") return ["ok", i + 1];
    if (s[i] !== ",") return ["invalid", i];
    i++;
  }
  return ["invalid", i];
}

export function answersObjectHasDuplicateKeys(body: string): boolean {
  const [status, end] = scanValue(body, skipWhitespace(body, 0), 0);
  if (status === "duplicate") return true;
  if (status === "invalid") return true;
  if (skipWhitespace(body, end) !== body.length) return true;
  return false;
}

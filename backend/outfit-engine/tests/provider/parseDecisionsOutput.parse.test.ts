import { describe, expect, it } from "vitest";
import { MAX_PROVIDER_RESPONSE_BYTES } from "../../src/provider/constants.js";
import { parseDecisionsResponseBody } from "../../src/provider/parseDecisionsOutput.js";

const MODEL = "mock/stylist-v0";

function body(answers: Record<string, unknown>): string {
  return JSON.stringify({
    model: MODEL,
    usage: { input_tokens: 1, output_tokens: 1 },
    answers,
  });
}

function bodyWithPad(pad: string): string {
  return JSON.stringify({
    model: MODEL,
    usage: { input_tokens: 1, output_tokens: 1 },
    answers: { slot_TOP: { type: "choice", choice: "g_1" } },
    _pad: pad,
  });
}

function utf8Len(s: string): number {
  return new TextEncoder().encode(s).length;
}

function trimPadToUtf8Bytes(target: number): string {
  let pad = "a".repeat(target);
  let json = bodyWithPad(pad);
  while (utf8Len(json) > target && pad.length > 0) {
    pad = pad.slice(0, -1);
    json = bodyWithPad(pad);
  }
  while (utf8Len(json) < target) {
    pad += "a";
    json = bodyWithPad(pad);
    if (utf8Len(json) > target) {
      pad = pad.slice(0, -1);
      json = bodyWithPad(pad);
      break;
    }
  }
  return json;
}

describe("parseDecisionsResponseBody", () => {
  it("builds a null-prototype answers map on success", () => {
    const result = parseDecisionsResponseBody(
      body({ slot_TOP: { type: "choice", choice: "g_1" } }),
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(Object.getPrototypeOf(result.value.answers)).toBe(null);
  });

  it("accepts bodies at exactly 64KB UTF-8 and rejects at 64KB+1", () => {
    const exact = trimPadToUtf8Bytes(MAX_PROVIDER_RESPONSE_BYTES);
    expect(utf8Len(exact)).toBe(MAX_PROVIDER_RESPONSE_BYTES);
    expect(parseDecisionsResponseBody(exact).ok).toBe(true);

    const over = exact + " ";
    expect(utf8Len(over)).toBe(MAX_PROVIDER_RESPONSE_BYTES + 1);
    expect(parseDecisionsResponseBody(over)).toEqual({
      ok: false,
      cause: "OUTPUT_PARSE",
    });
  });

  it("rejects UTF-16-short bodies whose UTF-8 size exceeds 64KB", () => {
    const twoByte = "\u00e9";
    const pad = twoByte.repeat(40_000);
    const json = bodyWithPad(pad);
    expect(json.length).toBeLessThan(MAX_PROVIDER_RESPONSE_BYTES);
    expect(utf8Len(json)).toBeGreaterThan(MAX_PROVIDER_RESPONSE_BYTES);
    expect(parseDecisionsResponseBody(json)).toEqual({
      ok: false,
      cause: "OUTPUT_PARSE",
    });

    const astral = "😀";
    const astralPad = astral.repeat(20_000);
    const astralJson = bodyWithPad(astralPad);
    expect(utf8Len(astralJson)).toBeGreaterThan(MAX_PROVIDER_RESPONSE_BYTES);
    expect(parseDecisionsResponseBody(astralJson)).toEqual({
      ok: false,
      cause: "OUTPUT_PARSE",
    });
  });

  it("maps malformed answer shapes to OUTPUT_SCHEMA", () => {
    const result = parseDecisionsResponseBody(
      body({ slot_TOP: "not-an-object" }),
    );
    expect(result).toEqual({ ok: false, cause: "OUTPUT_SCHEMA" });
  });

  it("maps invalid JSON to OUTPUT_PARSE", () => {
    expect(parseDecisionsResponseBody("{")).toEqual({
      ok: false,
      cause: "OUTPUT_PARSE",
    });
  });
});

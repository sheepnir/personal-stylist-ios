import { describe, expect, it } from "vitest";
import { createOwnRecord } from "../../src/provider/safeOwn.js";
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

describe("parseDecisionsResponseBody", () => {
  it("builds a null-prototype answers map on success", () => {
    const result = parseDecisionsResponseBody(
      body({ slot_TOP: { type: "choice", choice: "g_1" } }),
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(Object.getPrototypeOf(result.value.answers)).toBe(null);
  });

  it("rejects bodies over 64KB as OUTPUT_PARSE", () => {
    const huge = " ".repeat(MAX_PROVIDER_RESPONSE_BYTES + 1);
    expect(parseDecisionsResponseBody(huge)).toEqual({
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

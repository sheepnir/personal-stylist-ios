import { describe, expect, it } from "vitest";
import { answersObjectHasDuplicateKeys } from "../../src/provider/parseDecisionsDuplicateKeys.js";
import { parseDecisionsResponseBody } from "../../src/provider/parseDecisionsOutput.js";

describe("answersObjectHasDuplicateKeys", () => {
  it("detects duplicate keys in answers before JSON.parse would collapse them", () => {
    const body = `{
      "model": "mock/stylist-v0",
      "usage": { "input_tokens": 1, "output_tokens": 1 },
      "answers": {
        "slot_TOP": { "type": "choice", "choice": "g_aaaa" },
        "slot_TOP": { "type": "choice", "choice": "g_bbbb" }
      }
    }`;
    expect(answersObjectHasDuplicateKeys(body)).toBe(true);
    expect(parseDecisionsResponseBody(body)).toBeNull();
  });

  it("allows distinct answer keys", () => {
    const body = `{
      "model": "mock/stylist-v0",
      "usage": { "input_tokens": 1, "output_tokens": 1 },
      "answers": {
        "slot_TOP": { "type": "choice", "choice": "g_a" },
        "slot_BOTTOM": { "type": "choice", "choice": "g_b" }
      }
    }`;
    expect(answersObjectHasDuplicateKeys(body)).toBe(false);
  });
});

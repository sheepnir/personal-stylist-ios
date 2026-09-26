import { describe, expect, it } from "vitest";
import {
  MAX_JSON_DUPLICATE_SCAN_DEPTH,
  answersObjectHasDuplicateKeys,
} from "../../src/provider/parseDecisionsDuplicateKeys.js";
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
    expect(parseDecisionsResponseBody(body).ok).toBe(false);
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

  it("treats escape-equivalent keys as duplicates", () => {
    const body = `{"model":"m","usage":{"input_tokens":1,"output_tokens":1},"answers":{"a":1,"\\u0061":2}}`;
    expect(answersObjectHasDuplicateKeys(body)).toBe(true);
  });

  it("detects duplicate keys in nested objects", () => {
    const body = `{
      "model": "m",
      "usage": { "input_tokens": 1, "output_tokens": 1 },
      "answers": {
        "slot_TOP": { "type": "choice", "type": "choice", "choice": "g" }
      }
    }`;
    expect(answersObjectHasDuplicateKeys(body)).toBe(true);
  });

  it("detects duplicate keys inside arrays of objects", () => {
    const body = `{
      "model": "m",
      "usage": { "input_tokens": 1, "output_tokens": 1 },
      "answers": {
        "slot_TOP": { "type": "choice", "choice": "g", "meta": [ { "k": 1, "k": 2 } ] }
      }
    }`;
    expect(answersObjectHasDuplicateKeys(body)).toBe(true);
  });

  it("fails closed when nesting exceeds the scan depth limit", () => {
    let inner = "1";
    for (let d = 0; d <= MAX_JSON_DUPLICATE_SCAN_DEPTH; d++) {
      inner = `{"n":${inner}}`;
    }
    const body = `{"model":"m","usage":{"input_tokens":1,"output_tokens":1},"answers":{"slot_TOP":${inner}}}`;
    expect(answersObjectHasDuplicateKeys(body)).toBe(true);
  });
});

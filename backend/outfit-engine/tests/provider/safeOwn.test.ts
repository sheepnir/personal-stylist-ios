import { describe, expect, it } from "vitest";
import {
  createOwnRecord,
  isOwnStringToStringMap,
  ownGetString,
  ownHas,
  ownKeys,
} from "../../src/provider/safeOwn.js";

describe("safeOwn", () => {
  it("createOwnRecord uses a null prototype", () => {
    const rec = createOwnRecord<string>();
    expect(Object.getPrototypeOf(rec)).toBe(null);
    rec.g_1 = "uuid";
    expect(ownHas(rec, "g_1")).toBe(true);
    expect(ownHas(rec, "toString")).toBe(false);
  });

  it("ownKeys lists only own keys", () => {
    const rec = createOwnRecord<number>();
    rec.a = 1;
    rec.b = 2;
    expect(ownKeys(rec).sort()).toEqual(["a", "b"]);
  });

  it("ownGetString returns strings only for own keys", () => {
    const rec = createOwnRecord<string>();
    rec.good = "x";
    (rec as Record<string, unknown>).bad = 42;
    expect(ownGetString(rec, "good")).toBe("x");
    expect(ownGetString(rec, "bad")).toBeUndefined();
    expect(ownGetString(rec, "missing")).toBeUndefined();
  });

  it("isOwnStringToStringMap rejects empty or non-string values", () => {
    expect(isOwnStringToStringMap({ a: "ok" })).toBe(true);
    expect(isOwnStringToStringMap({ a: "" })).toBe(false);
    expect(isOwnStringToStringMap({ a: 1 })).toBe(false);
  });

  it("isOwnStringToStringMap ignores inherited properties", () => {
    const proto = { inherited: "uuid" };
    const child = Object.create(proto) as Record<string, unknown>;
    expect(isOwnStringToStringMap(child)).toBe(false);
  });

  it("isOwnStringToStringMap rejects polluted or custom prototypes", () => {
    const polluted = Object.create({ evil: "x" }) as Record<string, unknown>;
    polluted.g_1 = "uuid";
    expect(isOwnStringToStringMap(polluted)).toBe(false);
  });

  it("isOwnStringToStringMap rejects reserved own keys", () => {
    for (const key of ["__proto__", "constructor", "prototype"]) {
      expect(isOwnStringToStringMap({ [key]: "uuid" })).toBe(false);
    }
    expect(
      isOwnStringToStringMap(JSON.parse('{"__proto__":"x","g_1":"ok"}')),
    ).toBe(false);
    expect(isOwnStringToStringMap(JSON.parse('{"g_1":"ok"}'))).toBe(true);
  });
});

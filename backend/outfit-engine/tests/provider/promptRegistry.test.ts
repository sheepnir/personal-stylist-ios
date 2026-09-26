import { describe, expect, it, vi } from "vitest";
import * as promptContentHash from "../../src/provider/promptContentHash.js";
import {
  assertPromptRegistryIntegrity,
  buildProviderSuccessGeneration,
  CURRENT_STYLIST_PROMPT_VERSION,
  getStylistPromptByVersion,
  hashStylistPromptModule,
  hashStylistPromptVersionContent,
  outfitT2D1,
  OUTFIT_T2_D1_ANSWER_TYPES,
  OUTFIT_T2_D1_OPTION_DESCRIPTIONS,
  REGISTERED_PROMPT_CONTENT_HASHES,
  resolveRegisteredStylistPrompt,
  slotChoiceQuestionId,
  SLOT_CHOICE_QUESTION_SLOTS,
  UnregisteredPromptVersionError,
  PromptRegistryHashMismatchError,
} from "../../src/provider/index.js";
import { generateLocal, isLocalProblem } from "../../src/pipeline/generateLocal.js";
import {
  loadScenario,
  stage1InputFromScenario,
} from "../stage1/helpers.js";

const FORBIDDEN_CHAT_KEYS = new Set([
  "messages",
  "chat",
  "message",
  "system",
  "systemPrompt",
]);

function assertNoChatCompletionFields(value: unknown, seen = new WeakSet<object>()): void {
  if (value === null || typeof value !== "object") {
    return;
  }
  const objectValue = value as object;
  if (seen.has(objectValue)) {
    return;
  }
  seen.add(objectValue);

  if (Array.isArray(value)) {
    for (const entry of value) {
      assertNoChatCompletionFields(entry, seen);
    }
    return;
  }

  for (const key of Object.keys(value as Record<string, unknown>)) {
    expect(FORBIDDEN_CHAT_KEYS.has(key)).toBe(false);
    assertNoChatCompletionFields(
      (value as Record<string, unknown>)[key],
      seen,
    );
  }
}

describe("prompt registry (ADR-0001 §8)", () => {
  it("registered hash matches instructionText, optionDescriptions, and answerTypes", () => {
    expect(() => assertPromptRegistryIntegrity()).not.toThrow();
  });

  it("content hash excludes version string", () => {
    const base = hashStylistPromptModule(outfitT2D1);
    const withVersionInContent = hashStylistPromptVersionContent(
      outfitT2D1.instructionText,
      outfitT2D1.optionDescriptions,
      { ...(outfitT2D1.answerTypes as object), version: outfitT2D1.version },
    );
    expect(withVersionInContent).not.toBe(base);
    expect(
      hashStylistPromptVersionContent(
        outfitT2D1.instructionText,
        outfitT2D1.optionDescriptions,
        outfitT2D1.answerTypes,
      ),
    ).toBe(base);
  });

  it("fails when template content changes without a version bump", () => {
    const actual = hashStylistPromptModule(outfitT2D1);
    const registered = REGISTERED_PROMPT_CONTENT_HASHES["outfit-t2-d1"];
    expect(registered).toBeTruthy();
    expect(actual).toBe(registered);

    const tampered = hashStylistPromptVersionContent(
      `${outfitT2D1.instructionText}\n`,
      outfitT2D1.optionDescriptions,
      outfitT2D1.answerTypes,
    );
    expect(tampered).not.toBe(registered);
  });

  it("CURRENT_STYLIST_PROMPT resolves outfit-t2-d1 only (outfit-t2-v1 removed)", () => {
    expect(CURRENT_STYLIST_PROMPT_VERSION).toBe("outfit-t2-d1");
    expect(getStylistPromptByVersion("outfit-t2-d1")).toBe(outfitT2D1);
    expect(getStylistPromptByVersion("outfit-t2-v1")).toBeUndefined();
    expect(getStylistPromptByVersion("missing")).toBeUndefined();
  });

  it("registry lookups use Object.hasOwn (prototype pollution safe)", () => {
    expect(() => resolveRegisteredStylistPrompt("toString")).toThrow(
      UnregisteredPromptVersionError,
    );
    expect(Object.hasOwn(REGISTERED_PROMPT_CONTENT_HASHES, "outfit-t2-d1")).toBe(
      true,
    );
  });

  it("uses Decisions typed answers, not chat completion messages", () => {
    assertNoChatCompletionFields(outfitT2D1);
    expect(outfitT2D1.instructionText).not.toMatch(/\{g_/);
    expect(outfitT2D1.instructionText.toLowerCase()).not.toContain("gapreason");
    expect(JSON.stringify(outfitT2D1.answerTypes)).not.toContain("rationale");
    expect(JSON.stringify(outfitT2D1.answerTypes)).not.toContain("gapReason");
  });

  it("answerTypes keys mirror A-2 slot_<SLOT> contract (no accessory ids)", () => {
    const keys = Object.keys(OUTFIT_T2_D1_ANSWER_TYPES).sort();
    const expected = SLOT_CHOICE_QUESTION_SLOTS.map((slot) =>
      slotChoiceQuestionId(slot),
    ).sort();
    expect(keys).toEqual(expected);
    expect(keys.some((k) => k.startsWith("slot_ACCESSORY"))).toBe(false);
    for (const slot of SLOT_CHOICE_QUESTION_SLOTS) {
      expect(OUTFIT_T2_D1_ANSWER_TYPES[slotChoiceQuestionId(slot)]).toBeDefined();
      const desc = OUTFIT_T2_D1_OPTION_DESCRIPTIONS.find(
        (d) => d.questionId === slotChoiceQuestionId(slot),
      );
      expect(desc).toBeDefined();
    }
  });

  it("prompt exports are deep-frozen", () => {
    expect(Object.isFrozen(outfitT2D1)).toBe(true);
    expect(Object.isFrozen(outfitT2D1.optionDescriptions)).toBe(true);
    expect(Object.isFrozen(outfitT2D1.answerTypes)).toBe(true);
    expect(Object.isFrozen(OUTFIT_T2_D1_OPTION_DESCRIPTIONS)).toBe(true);
    expect(Object.isFrozen(OUTFIT_T2_D1_ANSWER_TYPES)).toBe(true);

    const hashBefore = hashStylistPromptModule(outfitT2D1);

    expect(() => {
      (outfitT2D1 as { instructionText: string }).instructionText = "tampered";
    }).toThrow();

    expect(hashStylistPromptModule(outfitT2D1)).toBe(hashBefore);
  });
});

describe("generation.promptVersion on every path", () => {
  it("deterministic generateLocal sets promptVersion to none", () => {
    const scenario = loadScenario("T2-01-sportcoat-mild-work");
    const s1 = stage1InputFromScenario(scenario);
    const result = generateLocal({
      wardrobe: s1.wardrobe,
      context: s1.context,
      anchorGarmentId: s1.anchorGarmentId,
      lockedAssignments: s1.lockedAssignments,
      options: s1.options,
      profile: s1.profile,
      sets: s1.sets,
    });
    expect(isLocalProblem(result)).toBe(false);
    if (isLocalProblem(result)) return;
    expect(result.generation.promptVersion).toBe("none");
  });

  it("provider success metadata names the registered prompt template", () => {
    const meta = buildProviderSuccessGeneration({
      candidateSetHash: "abc123",
      latencyMs: 42,
    });
    expect(meta.promptVersion).toBe("outfit-t2-d1");
    expect(getStylistPromptByVersion(meta.promptVersion)).toBe(outfitT2D1);
    expect(meta.modelId).toBe("mock/stylist-v0");
    expect(meta.candidateSetHash).toBe("abc123");
    expect(meta.fallbackLevel).toBe("NONE");
  });

  it("buildProviderSuccessGeneration rejects unregistered prompt versions", () => {
    expect(() =>
      buildProviderSuccessGeneration({
        candidateSetHash: "x",
        latencyMs: 1,
        promptVersion: "not-a-real-version",
      }),
    ).toThrow(UnregisteredPromptVersionError);

    expect(() => resolveRegisteredStylistPrompt("not-a-real-version")).toThrow(
      UnregisteredPromptVersionError,
    );
  });

  it("resolveRegisteredStylistPrompt rejects pinned hash mismatches", () => {
    const spy = vi
      .spyOn(promptContentHash, "hashStylistPromptModule")
      .mockReturnValue("deadbeef");
    expect(() => resolveRegisteredStylistPrompt("outfit-t2-d1")).toThrow(
      PromptRegistryHashMismatchError,
    );
    expect(() =>
      buildProviderSuccessGeneration({
        candidateSetHash: "x",
        latencyMs: 1,
        promptVersion: "outfit-t2-d1",
      }),
    ).toThrow(PromptRegistryHashMismatchError);
    spy.mockRestore();
  });
});

import { describe, expect, it, vi } from "vitest";
import * as promptContentHash from "../../src/provider/promptContentHash.js";
import {
  assertPromptRegistryIntegrity,
  buildProviderSuccessGeneration,
  CURRENT_STYLIST_PROMPT,
  CURRENT_STYLIST_PROMPT_VERSION,
  getStylistPromptByVersion,
  hashStylistPromptModule,
  hashStylistPromptVersionContent,
  outfitT2V1,
  OUTFIT_T2_V1_ANSWER_TYPES,
  OUTFIT_T2_V1_INPUT_SECTIONS,
  REGISTERED_PROMPT_CONTENT_HASHES,
  resolveRegisteredStylistPrompt,
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
  it("registered hash matches instruction, input sections, and answer types", () => {
    expect(() => assertPromptRegistryIntegrity()).not.toThrow();
  });

  it("fails when template content changes without a version bump", () => {
    const actual = hashStylistPromptModule(outfitT2V1);
    const registered = REGISTERED_PROMPT_CONTENT_HASHES["outfit-t2-v1"];
    expect(registered).toBeTruthy();
    expect(actual).toBe(registered);

    const tampered = hashStylistPromptVersionContent(
      `${outfitT2V1.instructionText}\n`,
      outfitT2V1.inputSections,
      outfitT2V1.answerTypes,
    );
    expect(tampered).not.toBe(registered);
  });

  it("CURRENT_STYLIST_PROMPT resolves to the repo module", () => {
    expect(CURRENT_STYLIST_PROMPT_VERSION).toBe("outfit-t2-v1");
    expect(getStylistPromptByVersion("outfit-t2-v1")).toBe(outfitT2V1);
    expect(getStylistPromptByVersion("missing")).toBeUndefined();
  });

  it("uses Decisions API prompt fields, not chat completion messages", () => {
    expect(outfitT2V1.instructionText.length).toBeGreaterThan(0);
    expect(outfitT2V1.inputSections.length).toBeGreaterThan(0);
    expect(outfitT2V1.answerTypes).toBeTruthy();
    assertNoChatCompletionFields(outfitT2V1);
  });

  it("inputSections use sectionKey labels, not Decisions question ids", () => {
    for (const section of outfitT2V1.inputSections) {
      expect(section.sectionKey).not.toMatch(/^slot_/);
      expect(section.sectionKey).not.toBe("candidates");
      expect(section.sectionKey).not.toBe("context");
      expect(section.sectionKey).not.toBe("profile");
      expect(section.sectionKey).not.toBe("options");
    }
  });

  it("prompt exports are deep-frozen", () => {
    expect(Object.isFrozen(outfitT2V1)).toBe(true);
    expect(Object.isFrozen(outfitT2V1.inputSections)).toBe(true);
    expect(Object.isFrozen(outfitT2V1.answerTypes)).toBe(true);
    expect(Object.isFrozen(OUTFIT_T2_V1_INPUT_SECTIONS)).toBe(true);
    expect(Object.isFrozen(OUTFIT_T2_V1_ANSWER_TYPES)).toBe(true);

    const hashBefore = hashStylistPromptModule(outfitT2V1);

    expect(() => {
      (outfitT2V1 as { instructionText: string }).instructionText = "tampered";
    }).toThrow();

    expect(() => {
      (OUTFIT_T2_V1_ANSWER_TYPES as { type?: string }).type = "string";
    }).toThrow();

    expect(hashStylistPromptModule(outfitT2V1)).toBe(hashBefore);
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
    expect(meta.promptVersion).toBe("outfit-t2-v1");
    expect(getStylistPromptByVersion(meta.promptVersion)).toBe(outfitT2V1);
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
    expect(() => resolveRegisteredStylistPrompt("outfit-t2-v1")).toThrow(
      PromptRegistryHashMismatchError,
    );
    expect(() =>
      buildProviderSuccessGeneration({
        candidateSetHash: "x",
        latencyMs: 1,
        promptVersion: "outfit-t2-v1",
      }),
    ).toThrow(PromptRegistryHashMismatchError);
    spy.mockRestore();
  });
});

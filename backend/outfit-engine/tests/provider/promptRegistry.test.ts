import { describe, expect, it } from "vitest";
import {
  assertPromptRegistryIntegrity,
  buildProviderSuccessGeneration,
  CURRENT_STYLIST_PROMPT,
  CURRENT_STYLIST_PROMPT_VERSION,
  getStylistPromptByVersion,
  hashPromptContent,
  outfitT2V1,
  REGISTERED_PROMPT_CONTENT_HASHES,
} from "../../src/provider/index.js";
import { generateLocal, isLocalProblem } from "../../src/pipeline/generateLocal.js";
import {
  loadScenario,
  stage1InputFromScenario,
} from "../stage1/helpers.js";

describe("prompt registry (ADR-0001 §8)", () => {
  it("registered hash matches live system + outputSchema for each version", () => {
    expect(() => assertPromptRegistryIntegrity()).not.toThrow();
  });

  it("fails when template content changes without a version bump", () => {
    const actual = hashPromptContent(
      outfitT2V1.system,
      outfitT2V1.outputSchema,
    );
    const registered = REGISTERED_PROMPT_CONTENT_HASHES["outfit-t2-v1"];
    expect(registered).toBeTruthy();
    expect(actual).toBe(registered);

    const tamperedSystem = `${outfitT2V1.system}\n`;
    const tampered = hashPromptContent(tamperedSystem, outfitT2V1.outputSchema);
    expect(tampered).not.toBe(registered);
  });

  it("CURRENT_STYLIST_PROMPT resolves to the repo module", () => {
    expect(CURRENT_STYLIST_PROMPT_VERSION).toBe("outfit-t2-v1");
    expect(getStylistPromptByVersion("outfit-t2-v1")).toBe(outfitT2V1);
    expect(getStylistPromptByVersion("missing")).toBeUndefined();
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

  it("outfit-t2-v1 render uses structured payload only", () => {
    const user = CURRENT_STYLIST_PROMPT.render({
      candidates: [{ token: "g_ab12", slot: "TOP" }],
      context: { occasion: "WORK_STANDARD" },
      profile: {},
      options: { requireSlots: ["TOP"] },
    });
    expect(() => JSON.parse(user)).not.toThrow();
  });
});

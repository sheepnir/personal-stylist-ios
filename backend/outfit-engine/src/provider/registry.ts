import { hashStylistPromptModule } from "./promptContentHash.js";
import { outfitT2D1 } from "./prompts/outfit-t2-d1.js";
import type { StylistPromptModule } from "./promptVersionTypes.js";

/** Every shipped prompt module (immutable; add new versions, do not edit in place). */
export const STYLIST_PROMPT_MODULES: readonly StylistPromptModule[] = [
  outfitT2D1,
] as const;

const byVersion = new Map<string, StylistPromptModule>(
  STYLIST_PROMPT_MODULES.map((module) => [module.version, module]),
);

/** Primary stylist prompt for provider-backed generate (ADR-0001 §8). */
export const CURRENT_STYLIST_PROMPT: StylistPromptModule = outfitT2D1;

export const CURRENT_STYLIST_PROMPT_VERSION = CURRENT_STYLIST_PROMPT.version;

/**
 * Registered SHA-256 content hashes (instructionText + optionDescriptions + answerTypes).
 * Update only when adding a new prompt version module — never when editing text in place.
 */
export const REGISTERED_PROMPT_CONTENT_HASHES: Readonly<Record<string, string>> = {
  "outfit-t2-d1": "5a460c36cfa76d915a0c4dae9809698a93dd6518515953398c10d45392d10d00",
};

export class UnregisteredPromptVersionError extends Error {
  constructor(version: string) {
    super(`Unregistered stylist prompt version: ${version}`);
    this.name = "UnregisteredPromptVersionError";
  }
}

export class PromptRegistryHashMismatchError extends Error {
  constructor(version: string, expected: string, actual: string) {
    super(
      `Prompt registry hash mismatch for ${version}: expected ${expected}, got ${actual}.`,
    );
    this.name = "PromptRegistryHashMismatchError";
  }
}

export function getStylistPromptByVersion(
  version: string,
): StylistPromptModule | undefined {
  return byVersion.get(version);
}

/** Resolves a version from the registry and verifies its pinned content hash. */
export function resolveRegisteredStylistPrompt(version: string): StylistPromptModule {
  const module = getStylistPromptByVersion(version);
  if (module === undefined) {
    throw new UnregisteredPromptVersionError(version);
  }
  if (!Object.hasOwn(REGISTERED_PROMPT_CONTENT_HASHES, version)) {
    throw new UnregisteredPromptVersionError(version);
  }
  const expected = REGISTERED_PROMPT_CONTENT_HASHES[version];
  const actual = hashStylistPromptModule(module);
  if (expected !== actual) {
    throw new PromptRegistryHashMismatchError(version, expected, actual);
  }
  return module;
}

/** Used by CI tests; throws if a module's live hash differs from the registry. */
export function assertPromptRegistryIntegrity(): void {
  for (const module of STYLIST_PROMPT_MODULES) {
    resolveRegisteredStylistPrompt(module.version);
  }
}

for (const module of STYLIST_PROMPT_MODULES) {
  if (!Object.hasOwn(REGISTERED_PROMPT_CONTENT_HASHES, module.version)) {
    throw new Error(
      `Prompt module ${module.version} has no REGISTERED_PROMPT_CONTENT_HASHES entry.`,
    );
  }
}

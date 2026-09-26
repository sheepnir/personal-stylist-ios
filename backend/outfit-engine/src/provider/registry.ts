import { hashStylistPromptModule } from "./promptContentHash.js";
import { outfitT2V1 } from "./prompts/outfit-t2-v1.js";
import type { StylistPromptModule } from "./promptVersionTypes.js";

/** Every shipped prompt module (immutable; add new versions, do not edit in place). */
export const STYLIST_PROMPT_MODULES: readonly StylistPromptModule[] = [
  outfitT2V1,
] as const;

const byVersion = new Map<string, StylistPromptModule>(
  STYLIST_PROMPT_MODULES.map((module) => [module.version, module]),
);

/** Primary stylist prompt for provider-backed generate (ADR-0001 §8). */
export const CURRENT_STYLIST_PROMPT: StylistPromptModule = outfitT2V1;

export const CURRENT_STYLIST_PROMPT_VERSION = CURRENT_STYLIST_PROMPT.version;

/**
 * Registered SHA-256 content hashes (instruction + input sections + answer types).
 * Update only when adding a new prompt version module — never when editing text in place.
 */
export const REGISTERED_PROMPT_CONTENT_HASHES: Readonly<Record<string, string>> = {
  "outfit-t2-v1": "60daa6e20e291e3eb0555b8944c71dacc0afe7d235557d8d7351e576bf04ffd9",
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
  const expected = REGISTERED_PROMPT_CONTENT_HASHES[version];
  if (expected === undefined) {
    throw new UnregisteredPromptVersionError(version);
  }
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

for (const version of STYLIST_PROMPT_MODULES.map((m) => m.version)) {
  if (!(version in REGISTERED_PROMPT_CONTENT_HASHES)) {
    throw new Error(`Prompt module ${version} has no REGISTERED_PROMPT_CONTENT_HASHES entry.`);
  }
}

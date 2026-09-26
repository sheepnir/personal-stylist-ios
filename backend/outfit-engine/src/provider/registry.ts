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
 * Registered SHA-256 content hashes (instruction + option descriptions + answer types).
 * Update only when adding a new prompt version module — never when editing text in place.
 */
export const REGISTERED_PROMPT_CONTENT_HASHES: Readonly<Record<string, string>> = {
  "outfit-t2-v1": "58cec0e7bc7553c2b652125623bb6b4ef511f5129c8eb90ebaa23cf2846fdf17",
};

export function getStylistPromptByVersion(
  version: string,
): StylistPromptModule | undefined {
  return byVersion.get(version);
}

/** Used by CI tests; throws if a module's live hash differs from the registry. */
export function assertPromptRegistryIntegrity(): void {
  for (const module of STYLIST_PROMPT_MODULES) {
    const expected = REGISTERED_PROMPT_CONTENT_HASHES[module.version];
    if (expected === undefined) {
      throw new Error(
        `Missing registered content hash for prompt version ${module.version}.`,
      );
    }
    const actual = hashStylistPromptModule(module);
    if (expected !== actual) {
      throw new Error(
        `Prompt registry hash mismatch for ${module.version}: expected ${expected}, got ${actual}. ` +
          "Bump the prompt version instead of editing an immutable module.",
      );
    }
  }
}

for (const version of STYLIST_PROMPT_MODULES.map((m) => m.version)) {
  if (!(version in REGISTERED_PROMPT_CONTENT_HASHES)) {
    throw new Error(`Prompt module ${version} has no REGISTERED_PROMPT_CONTENT_HASHES entry.`);
  }
}

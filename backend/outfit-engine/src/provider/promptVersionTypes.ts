/**
 * Versioned stylist prompt modules for the provider Decisions API (issue #26 A-1).
 * Pure definitions — no network, no chat roles or message arrays.
 */

/** Describes one decision input facet (option descriptions in the Decisions API). */
export interface StylistPromptOptionDescription {
  readonly id: string;
  readonly description: string;
}

/**
 * Immutable prompt version: instruction text, option descriptions, and answer types.
 * Hashed together for the registry guard (ADR-0001 §8).
 */
export interface StylistPromptModule {
  readonly version: string;
  readonly instructionText: string;
  readonly optionDescriptions: readonly StylistPromptOptionDescription[];
  readonly answerTypes: unknown;
}

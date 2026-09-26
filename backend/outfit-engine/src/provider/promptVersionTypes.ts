/**
 * Versioned stylist prompt modules for the provider Decisions API (issue #26 A-1).
 * Pure definitions — no network, no chat roles or message arrays.
 */

/** Describes typed choice options for one slot question (`slot_<SLOT>`). */
export interface StylistPromptOptionDescription {
  readonly questionId: string;
  readonly description: string;
}

/**
 * Immutable prompt version: instruction text, option descriptions, and answer types.
 * Content hash covers these three fields only (not `version`) — ADR-0001 §8.
 */
export interface StylistPromptModule {
  readonly version: string;
  readonly instructionText: string;
  readonly optionDescriptions: readonly StylistPromptOptionDescription[];
  readonly answerTypes: unknown;
}

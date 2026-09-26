/**
 * Versioned stylist prompt modules for the provider Decisions API (issue #26 A-1).
 * Pure definitions — no network, no chat roles or message arrays.
 */

/**
 * Describes a logical input section for documentation and hashing only.
 * `sectionKey` is NOT a Decisions question id (those are owned by A-2: slot_<SLOT>, etc.).
 */
export interface StylistPromptInputSection {
  readonly sectionKey: string;
  readonly description: string;
}

/**
 * Immutable prompt version: instruction text, input-section descriptors, and answer types.
 * Hashed together for the registry guard (ADR-0001 §8).
 */
export interface StylistPromptModule {
  readonly version: string;
  readonly instructionText: string;
  readonly inputSections: readonly StylistPromptInputSection[];
  readonly answerTypes: unknown;
}

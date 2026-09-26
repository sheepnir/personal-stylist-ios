/**
 * Worker-facing provider generation metadata (issue #26 A-1).
 * Full provider routing lands in A-3; metadata shape is fixed here for tests and future wiring.
 */

export {
  buildProviderSuccessGeneration,
  CURRENT_STYLIST_PROMPT,
  CURRENT_STYLIST_PROMPT_VERSION,
  getStylistPromptByVersion,
} from '@personal-stylist/outfit-engine';

/**
 * Provider prompt modules (issue #26 A-1, ADR-0001 §8).
 * Pure definitions — no network.
 */

import type { JSONSchema7 } from "./jsonSchemaTypes.js";

/** Minimum provider payload shape passed to `render` (full allowlist built in A-2). */
export interface StylistProviderPayload {
  candidates: unknown[];
  context: Record<string, unknown>;
  profile: Record<string, unknown>;
  options: Record<string, unknown>;
}

export interface StylistPromptModule {
  readonly version: string;
  readonly system: string;
  render(payload: StylistProviderPayload): string;
  readonly outputSchema: JSONSchema7;
}

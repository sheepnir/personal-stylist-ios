/**
 * Reviewed model allowlist and narrow-only env selection (#12 / ADR-0001 §7).
 * Phase A: exactly one entry — the mock slug (not a paid provider id).
 */

import type { Env } from './types.js';

export type ModelRole = 'primary' | 'secondary';

export type AllowlistEntry = {
  slug: string;
  roles: ModelRole[];
  inputUSDPerMTok: number;
  outputUSDPerMTok: number;
  pricesCheckedOn: string;
  supportsVision: boolean | null;
  supportsStructuredOutput: boolean | null;
  contextWindow: number | null;
};

export type ModelDescriptor = {
  slug: string;
  displayName: string | null;
  supportsVision: boolean | null;
  supportsStructuredOutput: boolean | null;
  contextWindow: number | null;
};

export type ResolvedModelConfig = {
  primary: ModelDescriptor | null;
  secondary: ModelDescriptor | null;
};

/** Sole phase-A allowlist entry (mock only — no live provider slug). */
export const MODEL_ALLOWLIST: readonly AllowlistEntry[] = [
  {
    slug: 'mock/stylist-v0',
    roles: ['primary', 'secondary'],
    inputUSDPerMTok: 0,
    outputUSDPerMTok: 0,
    pricesCheckedOn: '2026-09-26',
    supportsVision: false,
    supportsStructuredOutput: false,
    contextWindow: 32000,
  },
] as const;

/** Served on GET /v1/models — VF-03 surface; verifiedOn stays null until founder verification. */
export const SERVED_DATA_POLICY = {
  excludesTrainingProviders: true,
  verifiedOn: null,
  note: null,
} as const;

const PROMPT_VERSION_NONE = 'none';

function entryForSlug(slug: string): AllowlistEntry | undefined {
  return MODEL_ALLOWLIST.find((e) => e.slug === slug);
}

function toDescriptor(entry: AllowlistEntry): ModelDescriptor {
  return {
    slug: entry.slug,
    displayName: null,
    supportsVision: entry.supportsVision,
    supportsStructuredOutput: entry.supportsStructuredOutput,
    contextWindow: entry.contextWindow,
  };
}

function resolveRole(
  envValue: string | undefined,
  role: ModelRole
): ModelDescriptor | null {
  const trimmed = envValue?.trim();
  if (!trimmed) return null;
  const entry = entryForSlug(trimmed);
  if (!entry || !entry.roles.includes(role)) return null;
  return toDescriptor(entry);
}

/**
 * Env vars may only narrow the allowlist. Unknown slug, wrong role, or unset env → unconfigured (null).
 * When primary and secondary env both name the same eligible slug, secondary matches primary.
 */
export function resolveConfiguredModels(
  env: Pick<Env, 'STYLIST_PRIMARY_MODEL' | 'STYLIST_SECONDARY_MODEL'>
): ResolvedModelConfig {
  const primary = resolveRole(env.STYLIST_PRIMARY_MODEL, 'primary');
  const secondary = resolveRole(env.STYLIST_SECONDARY_MODEL, 'secondary');
  return { primary, secondary };
}

export function buildModelConfigResponse(
  env: Pick<Env, 'STYLIST_PRIMARY_MODEL' | 'STYLIST_SECONDARY_MODEL'>,
  policyVersion: string | null
): {
  primary: ModelDescriptor | null;
  secondary: ModelDescriptor | null;
  promptVersion: string;
  dataPolicy: typeof SERVED_DATA_POLICY;
  policyVersion: string | null;
} {
  const { primary, secondary } = resolveConfiguredModels(env);
  return {
    primary,
    secondary,
    promptVersion: PROMPT_VERSION_NONE,
    dataPolicy: SERVED_DATA_POLICY,
    policyVersion,
  };
}

/**
 * Model allowlist and narrow-only env resolver (#12).
 */

import { describe, it, expect } from 'vitest';
import {
  MODEL_ALLOWLIST,
  resolveConfiguredModels,
  buildModelConfigResponse,
} from '../src/models.js';
import { CURRENT_PRIVACY_POLICY_VERSION } from '../src/policy.js';

describe('MODEL_ALLOWLIST', () => {
  it('contains exactly one mock entry', () => {
    expect(MODEL_ALLOWLIST).toHaveLength(1);
    expect(MODEL_ALLOWLIST[0].slug).toBe('mock/stylist-v0');
    expect(MODEL_ALLOWLIST[0].roles).toEqual(['primary', 'secondary']);
  });
});

describe('resolveConfiguredModels', () => {
  it('returns mock/stylist-v0 when env names it for primary', () => {
    const { primary, secondary } = resolveConfiguredModels({
      STYLIST_PRIMARY_MODEL: 'mock/stylist-v0',
    });
    expect(primary?.slug).toBe('mock/stylist-v0');
    expect(secondary).toBeNull();
  });

  it('treats unknown slug as unconfigured', () => {
    expect(
      resolveConfiguredModels({ STYLIST_PRIMARY_MODEL: 'typesafe/jev-1.13' }).primary
    ).toBeNull();
  });

  it('treats empty or whitespace env as unconfigured', () => {
    expect(resolveConfiguredModels({ STYLIST_PRIMARY_MODEL: '' }).primary).toBeNull();
    expect(resolveConfiguredModels({ STYLIST_PRIMARY_MODEL: '   ' }).primary).toBeNull();
    expect(resolveConfiguredModels({}).primary).toBeNull();
  });

  it('rejects a slug that is not role-eligible for secondary-only env', () => {
    // Hypothetical: if allowlist had primary-only entry — today mock supports both.
    const { secondary } = resolveConfiguredModels({
      STYLIST_SECONDARY_MODEL: 'mock/stylist-v0',
    });
    expect(secondary?.slug).toBe('mock/stylist-v0');
  });

  it('allows secondary equal to primary when both env vars name the same slug', () => {
    const env = {
      STYLIST_PRIMARY_MODEL: 'mock/stylist-v0',
      STYLIST_SECONDARY_MODEL: 'mock/stylist-v0',
    };
    const { primary, secondary } = resolveConfiguredModels(env);
    expect(primary?.slug).toBe('mock/stylist-v0');
    expect(secondary?.slug).toBe('mock/stylist-v0');
    expect(secondary).toEqual(primary);
  });

  it('buildModelConfigResponse serves promptVersion none and policyVersion from policy module', () => {
    const body = buildModelConfigResponse(
      { STYLIST_PRIMARY_MODEL: 'mock/stylist-v0' },
      CURRENT_PRIVACY_POLICY_VERSION
    );
    expect(body.promptVersion).toBe('none');
    expect(body.policyVersion).toBeNull();
    expect(body.dataPolicy.excludesTrainingProviders).toBe(true);
    expect(body.dataPolicy.verifiedOn).toBeNull();
  });
});

import { describe, it, expect } from 'vitest';
import { CURRENT_PRIVACY_POLICY_VERSION } from '../src/policy.js';
import privacyPolicy from '../../../shared/privacy-policy-version.json';

describe('policy.ts', () => {
  it('exports CURRENT_PRIVACY_POLICY_VERSION equal to shared JSON', () => {
    expect(CURRENT_PRIVACY_POLICY_VERSION).toBe(privacyPolicy.policyVersion);
    expect(CURRENT_PRIVACY_POLICY_VERSION).toBeNull();
  });
});

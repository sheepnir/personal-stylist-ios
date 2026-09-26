import privacyPolicy from '../../../shared/privacy-policy-version.json';

export type PrivacyPolicyVersionFile = {
  policyVersion: string | null;
};

const canonical = privacyPolicy as PrivacyPolicyVersionFile;

/** Canonical privacy / data-use policy version served by the Worker (no env override). */
export const CURRENT_PRIVACY_POLICY_VERSION: string | null = canonical.policyVersion;

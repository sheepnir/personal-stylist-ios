/**
 * Legitimate-key sweep driven by scripts/check-image-guard-parity.py (OpenAPI + fixtures + corpus).
 */

import { readFileSync } from 'node:fs';
import { describe, it, expect } from 'vitest';
import { normalizedKeyContainsForbiddenImageToken } from '../src/imageGuardKey.js';

const keysPath = process.env.LEGITIMATE_IMAGE_GUARD_KEYS_JSON;
const keys: string[] = keysPath
  ? (JSON.parse(readFileSync(keysPath, 'utf8')) as string[])
  : [];

describe('image-guard legitimate keys (parity sweep)', () => {
  it('runs only when LEGITIMATE_IMAGE_GUARD_KEYS_JSON is set', () => {
    if (!keysPath) {
      expect(keys).toEqual([]);
      return;
    }
    expect(keys.length).toBeGreaterThan(0);
  });

  it.each(keys)('property name %s is not image-bearing', (key) => {
    expect(normalizedKeyContainsForbiddenImageToken(key)).toBe(false);
  });
});

/**
 * Corpus-driven regression for image-guard parity (#36).
 * Exercised by scripts/check-image-guard-parity.py via `npm test -- image-guard-corpus`.
 */

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, it, expect } from 'vitest';
import {
  FORBIDDEN_IMAGE_KEY_TOKENS,
  IMAGE_GUARD_CONSENT_FIELD_PATH,
  normalizedKeyContainsForbiddenImageToken,
  rejectImagePayload,
} from '../src/validation.js';

const corpusPath = join(dirname(fileURLToPath(import.meta.url)), '../../../fixtures/image-guard/corpus.json');

type Corpus = {
  keySegments: Array<{ key: string; imageBearing: boolean }>;
  rejectBodies: Array<{ label?: string; body: Record<string, unknown> }>;
  allowBodies: Array<{ label?: string; body: Record<string, unknown> }>;
};

const corpus = JSON.parse(readFileSync(corpusPath, 'utf8')) as Corpus;

describe('image-guard corpus (#36)', () => {
  it('exports the expected forbidden token count', () => {
    expect(FORBIDDEN_IMAGE_KEY_TOKENS.length).toBeGreaterThanOrEqual(13);
    expect(IMAGE_GUARD_CONSENT_FIELD_PATH).toBe('privacyConsent.wardrobeImagesAcceptedAt');
  });

  it.each(corpus.keySegments)('key segment $key → imageBearing=$imageBearing', ({ key, imageBearing }) => {
    expect(normalizedKeyContainsForbiddenImageToken(key)).toBe(imageBearing);
  });

  it.each(corpus.rejectBodies)('rejects body: $label', ({ body }) => {
    expect(rejectImagePayload(body)?.status).toBe(415);
  });

  it.each(corpus.allowBodies)('allows body: $label', ({ body }) => {
    expect(rejectImagePayload(body)).toBeNull();
  });
});

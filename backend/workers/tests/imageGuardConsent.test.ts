/**
 * Unit tests for the shared RFC 3339 consent timestamp rule (#36).
 */

import { describe, it, expect } from 'vitest';
import {
  isAllowedWardrobeImagesAcceptedAtRfc3339,
  isAllowedWardrobeImagesAcceptedAtValue,
  rfc3339CalendarDateValid,
} from '../src/imageGuardConsent.js';

describe('imageGuardConsent RFC 3339 (#36)', () => {
  it('rejects non-ASCII digits, trailing newline, and accepts year 0050 and 0000', () => {
    expect(isAllowedWardrobeImagesAcceptedAtRfc3339('２026-09-20T12:00:00Z')).toBe(false);
    expect(isAllowedWardrobeImagesAcceptedAtRfc3339('2026-09-20T12:00:00Z\n')).toBe(false);
    expect(isAllowedWardrobeImagesAcceptedAtRfc3339('0050-06-15T12:00:00Z')).toBe(true);
    expect(isAllowedWardrobeImagesAcceptedAtRfc3339('0000-01-01T00:00:00Z')).toBe(true);
  });

  it('rejects out-of-range time and offset components', () => {
    expect(isAllowedWardrobeImagesAcceptedAtRfc3339('2026-09-20T24:00:00Z')).toBe(false);
    expect(isAllowedWardrobeImagesAcceptedAtRfc3339('2026-09-20T12:60:00Z')).toBe(false);
    expect(isAllowedWardrobeImagesAcceptedAtRfc3339('2026-09-20T12:00:00+24:00')).toBe(false);
    expect(isAllowedWardrobeImagesAcceptedAtRfc3339('2026-09-20T12:00:61Z')).toBe(false);
  });

  it('rejects consent values longer than 64 characters before regex', () => {
    const value = `${'2026-09-20T12:00:00Z'}${'0'.repeat(45)}`;
    expect(value.length).toBe(65);
    expect(isAllowedWardrobeImagesAcceptedAtRfc3339(value)).toBe(false);
  });

  it('uses setUTCFullYear-style calendar validation for low years', () => {
    expect(rfc3339CalendarDateValid(50, 6, 15)).toBe(true);
    expect(rfc3339CalendarDateValid(2026, 2, 31)).toBe(false);
  });

  it('rejects U+2028 and U+2029 in consent timestamps', () => {
    expect(isAllowedWardrobeImagesAcceptedAtRfc3339('2026-09-20T12:00:00Z\u2028')).toBe(false);
    expect(isAllowedWardrobeImagesAcceptedAtRfc3339('\u20292026-09-20T12:00:00Z')).toBe(false);
  });

  it('rejects non-string values', () => {
    expect(isAllowedWardrobeImagesAcceptedAtValue(null)).toBe(false);
    expect(isAllowedWardrobeImagesAcceptedAtValue(1)).toBe(false);
    expect(isAllowedWardrobeImagesAcceptedAtValue({})).toBe(false);
  });
});

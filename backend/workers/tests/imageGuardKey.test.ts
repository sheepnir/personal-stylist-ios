import { describe, it, expect } from 'vitest';
import {
  ECMA_SCRIPT_WHITESPACE_CODE_POINTS,
  IMAGE_GUARD_KEY_SEPARATOR_CODE_POINTS,
  IMAGE_GUARD_PRINTABLE_ASCII_MAX,
  IMAGE_GUARD_PRINTABLE_ASCII_MIN,
  isImageGuardKeySeparatorCodePoint,
  normalizeImageGuardKey,
  normalizedKeyContainsForbiddenImageToken,
  objectKeyFailsPrintableAsciiRule,
} from '../src/imageGuardKey.js';

describe('imageGuardKey printable ASCII rule', () => {
  it('rejects keys outside printable ASCII', () => {
    expect(objectKeyFailsPrintableAsciiRule('id')).toBe(false);
    expect(objectKeyFailsPrintableAsciiRule('im\u200bage')).toBe(true);
    expect(normalizedKeyContainsForbiddenImageToken('im\u200bage')).toBe(true);
    expect(normalizedKeyContainsForbiddenImageToken('\u0438mage')).toBe(true);
    expect(normalizedKeyContainsForbiddenImageToken('\uFF49mage')).toBe(true);
  });

  it('exports ASCII bounds for parity', () => {
    expect(IMAGE_GUARD_PRINTABLE_ASCII_MIN).toBe(0x20);
    expect(IMAGE_GUARD_PRINTABLE_ASCII_MAX).toBe(0x7e);
    expect(IMAGE_GUARD_KEY_SEPARATOR_CODE_POINTS).toEqual([0x5f, 0x2d, 0x2e]);
    expect(ECMA_SCRIPT_WHITESPACE_CODE_POINTS.length).toBeGreaterThan(20);
  });
});

describe('imageGuardKey word separators', () => {
  it('treats dot and whitespace like underscore and hyphen', () => {
    expect(isImageGuardKeySeparatorCodePoint(' '.codePointAt(0)!)).toBe(true);
    expect(isImageGuardKeySeparatorCodePoint('.'.codePointAt(0)!)).toBe(true);
    expect(normalizeImageGuardKey('pixel data')).toBe('pixeldata');
    expect(normalizedKeyContainsForbiddenImageToken('bit map')).toBe(true);
    expect(normalizedKeyContainsForbiddenImageToken('pho.to')).toBe(true);
  });
});

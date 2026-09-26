import { describe, it, expect } from 'vitest';
import {
  isDefaultIgnorableCodePoint,
  isImageGuardKeySeparator,
  normalizeImageGuardKey,
  normalizedKeyContainsForbiddenImageToken,
} from '../src/imageGuardKey.js';

describe('imageGuardKey default-ignorable stripping', () => {
  it('recognizes default-ignorable code points', () => {
    expect(isDefaultIgnorableCodePoint(0x200b)).toBe(true);
    expect(isDefaultIgnorableCodePoint(0x200c)).toBe(true);
    expect(isDefaultIgnorableCodePoint(0x200d)).toBe(true);
    expect(isDefaultIgnorableCodePoint(0x2060)).toBe(true);
    expect(isDefaultIgnorableCodePoint(0xfeff)).toBe(true);
    expect(isDefaultIgnorableCodePoint(0x00ad)).toBe(true);
    expect(isDefaultIgnorableCodePoint(0xfe00)).toBe(true);
    expect(isDefaultIgnorableCodePoint(0x61)).toBe(false);
  });

  it('strips ignorable characters before forbidden token match', () => {
    expect(normalizeImageGuardKey('im\u200bage')).toBe('image');
    expect(normalizedKeyContainsForbiddenImageToken('im\u200bage')).toBe(true);
    expect(normalizedKeyContainsForbiddenImageToken('IM\u200bAGE')).toBe(true);
    expect(normalizedKeyContainsForbiddenImageToken('photo\uFEFFUrl')).toBe(true);
    expect(normalizedKeyContainsForbiddenImageToken('pixel\u200bdata')).toBe(true);
    expect(normalizedKeyContainsForbiddenImageToken('maſterlabel')).toBe(false);
    expect(normalizedKeyContainsForbiddenImageToken('maſterimage')).toBe(true);
  });
});

describe('imageGuardKey word separators', () => {
  it('treats dot and whitespace like underscore and hyphen', () => {
    expect(isImageGuardKeySeparator(' '.charCodeAt(0))).toBe(true);
    expect(isImageGuardKeySeparator('.'.charCodeAt(0))).toBe(true);
    expect(normalizeImageGuardKey('pixel data')).toBe('pixeldata');
    expect(normalizeImageGuardKey('pixel.data')).toBe('pixeldata');
    expect(normalizeImageGuardKey('pixel_data')).toBe('pixeldata');
    expect(normalizedKeyContainsForbiddenImageToken('bit map')).toBe(true);
    expect(normalizedKeyContainsForbiddenImageToken('pho.to')).toBe(true);
    expect(normalizedKeyContainsForbiddenImageToken('thu.mb')).toBe(true);
  });
});

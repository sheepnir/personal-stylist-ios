import { describe, it, expect } from 'vitest';
import {
  isDefaultIgnorableCodePoint,
  normalizeImageGuardKey,
  normalizedKeyContainsForbiddenImageToken,
} from '../src/imageGuardKey.js';

describe('imageGuardKey default-ignorable stripping', () => {
  it('recognizes default-ignorable code points', () => {
    expect(isDefaultIgnorableCodePoint(0x200b)).toBe(true);
    expect(isDefaultIgnorableCodePoint(0xfeff)).toBe(true);
    expect(isDefaultIgnorableCodePoint(0xfe00)).toBe(true);
    expect(isDefaultIgnorableCodePoint(0x61)).toBe(false);
  });

  it('strips ignorable characters before forbidden token match', () => {
    expect(normalizeImageGuardKey('im\u200bage')).toBe('image');
    expect(normalizedKeyContainsForbiddenImageToken('im\u200bage')).toBe(true);
    expect(normalizedKeyContainsForbiddenImageToken('IM\u200bAGE')).toBe(true);
    expect(normalizedKeyContainsForbiddenImageToken('photo\uFEFFUrl')).toBe(true);
    expect(normalizedKeyContainsForbiddenImageToken('maſterlabel')).toBe(false);
    expect(normalizedKeyContainsForbiddenImageToken('maſterimage')).toBe(true);
  });
});

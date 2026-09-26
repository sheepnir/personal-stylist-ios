/**
 * Key-segment normalization for the image guard (#36).
 */

/** Substrings matched after {@link normalizeImageGuardKey} on printable-ASCII keys. */
export const FORBIDDEN_IMAGE_KEY_TOKENS = [
  'image',
  'imagedata',
  'imagebase64',
  'thumbnail',
  'thumb',
  'photo',
  'masterimage',
  'processedimage',
  'pixeldata',
  'bitmap',
  'imagery',
  'photography',
  'thumbsup',
] as const;

export const IMAGE_GUARD_PRINTABLE_ASCII_MIN = 0x20;
export const IMAGE_GUARD_PRINTABLE_ASCII_MAX = 0x7e;

/** Stripped before forbidden-token matching (word separators). */
export const IMAGE_GUARD_KEY_SEPARATOR_CODE_POINTS = [0x5f, 0x2d, 0x2e] as const;

/** ECMAScript WhiteSpace + LineTerminator (same set as value `trimStart()`). */
export const ECMA_SCRIPT_WHITESPACE_CODE_POINTS = [
  0x0009, 0x000a, 0x000b, 0x000c, 0x000d, 0x0020, 0x00a0, 0x1680,
  0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200a,
  0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff,
] as const;

const ECMA_SCRIPT_WHITESPACE_CODES = new Set<number>(ECMA_SCRIPT_WHITESPACE_CODE_POINTS);

export function objectKeyFailsPrintableAsciiRule(key: string): boolean {
  for (const char of key) {
    const code = char.codePointAt(0)!;
    if (code < IMAGE_GUARD_PRINTABLE_ASCII_MIN || code > IMAGE_GUARD_PRINTABLE_ASCII_MAX) {
      return true;
    }
  }
  return false;
}

export function isImageGuardKeySeparatorCodePoint(code: number): boolean {
  if (code === 0x5f || code === 0x2d || code === 0x2e) return true;
  return ECMA_SCRIPT_WHITESPACE_CODES.has(code);
}

/** Lowercase ASCII A–Z; strip separators on printable-ASCII keys only. */
export function normalizeImageGuardKey(key: string): string {
  let normalized = '';
  for (const char of key) {
    const code = char.codePointAt(0)!;
    if (isImageGuardKeySeparatorCodePoint(code)) continue;
    if (code >= 65 && code <= 90) normalized += String.fromCodePoint(code + 32);
    else normalized += char;
  }
  return normalized;
}

export function normalizedKeyContainsForbiddenImageToken(key: string): boolean {
  if (objectKeyFailsPrintableAsciiRule(key)) return true;
  const normalized = normalizeImageGuardKey(key);
  return FORBIDDEN_IMAGE_KEY_TOKENS.some((token) => normalized.includes(token));
}

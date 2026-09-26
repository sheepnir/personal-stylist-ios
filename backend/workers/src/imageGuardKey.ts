/**
 * Key-segment normalization for the image guard (#36).
 */

/** Substrings matched after {@link normalizeImageGuardKey}. */
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

/** ECMAScript WhiteSpace + LineTerminator (same set as value `trimStart()`). */
const ECMA_SCRIPT_WHITESPACE_CODES = new Set<number>([
  0x0009, 0x000a, 0x000b, 0x000c, 0x000d, 0x0020, 0x00a0, 0x1680,
  0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200a,
  0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff,
]);

export function isDefaultIgnorableCodePoint(code: number): boolean {
  if (code === 0x00ad || code === 0x034f || code === 0x180e || code === 0xfeff) return true;
  if (code >= 0x200b && code <= 0x200f) return true;
  if (code >= 0x2060 && code <= 0x206f) return true;
  if (code >= 0xfe00 && code <= 0xfe0f) return true;
  return /\p{Cf}/u.test(String.fromCodePoint(code));
}

export function isImageGuardKeySeparator(code: number): boolean {
  if (code === 0x5f || code === 0x2d || code === 0x2e) return true;
  return ECMA_SCRIPT_WHITESPACE_CODES.has(code);
}

/** Lowercase ASCII A–Z; strip separators, default-ignorable code points, then token match. */
export function normalizeImageGuardKey(key: string): string {
  let normalized = '';
  for (let i = 0; i < key.length; i++) {
    const code = key.charCodeAt(i);
    if (isDefaultIgnorableCodePoint(code)) continue;
    if (isImageGuardKeySeparator(code)) continue;
    if (code >= 65 && code <= 90) normalized += String.fromCharCode(code + 32);
    else normalized += key[i];
  }
  return normalized;
}

export function normalizedKeyContainsForbiddenImageToken(key: string): boolean {
  const normalized = normalizeImageGuardKey(key);
  return FORBIDDEN_IMAGE_KEY_TOKENS.some((token) => normalized.includes(token));
}
